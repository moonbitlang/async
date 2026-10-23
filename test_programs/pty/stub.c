/* Copyright 2026 International Digital Economy Academy
 * Licensed under the Apache License, Version 2.0.
 */

#ifndef _WIN32
#define _XOPEN_SOURCE 600
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

#ifdef _WIN32
#include <windows.h>
typedef HANDLE file_handle;
typedef HPCON terminal_handle;
#define INPUT_HANDLE GetStdHandle(STD_INPUT_HANDLE)
#define OUTPUT_HANDLE GetStdHandle(STD_OUTPUT_HANDLE)
#define CONTROL_HANDLE GetStdHandle(STD_ERROR_HANDLE)
#else
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
typedef int file_handle;
typedef int terminal_handle;
#define INPUT_HANDLE STDIN_FILENO
#define OUTPUT_HANDLE STDOUT_FILENO
#define CONTROL_HANDLE STDERR_FILENO
#endif

// stdin: "input <byte count>\n" followed by that many bytes, or
//        "resize <rows> <cols>\n". Commands must not be interleaved.
// stdout: the unmodified PTY output stream (rendered UTF-8/VT on ConPTY).
// stderr: "ok\n" after a resize, or an error diagnostic.
// Closing stdin finishes the script; the caller must also let the child exit.
// Unix signal exits become 128 + signal; Windows exit codes are unchanged.

static int read_some(file_handle file, void *data, size_t size, size_t *count) {
#ifdef _WIN32
  DWORD n;
  if (!ReadFile(file, data, (DWORD)size, &n, NULL))
    return 0;
#else
  ssize_t n;
  do {
    n = read(file, data, size);
  } while (n < 0 && errno == EINTR);
  if (n < 0)
    return 0;
#endif
  *count = (size_t)n;
  return 1;
}

static int write_all(file_handle file, const void *data, size_t size) {
  const char *p = data;
  while (size) {
#ifdef _WIN32
    DWORD n;
    if (!WriteFile(file, p, (DWORD)size, &n, NULL) || n == 0)
      return 0;
#else
    ssize_t n = write(file, p, size);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      return 0;
#endif
    p += n;
    size -= n;
  }
  return 1;
}

static int resize_terminal(terminal_handle terminal, unsigned rows,
                           unsigned cols) {
#ifdef _WIN32
  COORD size = {(SHORT)cols, (SHORT)rows};
  return SUCCEEDED(ResizePseudoConsole(terminal, size));
#else
  struct winsize size = {0};
  size.ws_row = (unsigned short)rows;
  size.ws_col = (unsigned short)cols;
  return ioctl(terminal, TIOCSWINSZ, &size) == 0;
#endif
}

static int read_commands(terminal_handle terminal, file_handle input) {
  char header[80], buf[4096];
  for (;;) {
    size_t n, pos = 0;
    do {
      if (!read_some(INPUT_HANDLE, header + pos, 1, &n))
        return 0;
      if (n == 0)
        return pos == 0;
      if (++pos == sizeof(header))
        return 0;
    } while (header[pos - 1] != '\n');
    header[pos] = 0;
    unsigned int length, rows, cols;
    char extra;
    if (sscanf(header, "input %u %c", &length, &extra) == 1) {
      while (length) {
        size_t count = length < sizeof(buf) ? length : sizeof(buf);
        if (!read_some(INPUT_HANDLE, buf, count, &n) || n == 0 ||
            !write_all(input, buf, n))
          return 0;
        length -= (unsigned int)n;
      }
    } else if (sscanf(header, "resize %u %u %c", &rows, &cols, &extra) == 2 &&
               rows > 0 && rows <= 32767 && cols > 0 && cols <= 32767) {
      if (!resize_terminal(terminal, rows, cols) ||
          !write_all(CONTROL_HANDLE, "ok\n", 3))
        return 0;
    } else {
      return 0;
    }
  }
}

static int copy_output_stream(file_handle output) {
  char buf[4096];
  size_t n;
  int writable = 1;
  while (read_some(output, buf, sizeof(buf), &n) && n) {
    // Keep draining after stdout closes: ClosePseudoConsole can wait for this
    // pipe on older Windows versions, and a Unix child may be blocked writing.
    if (writable)
      writable = write_all(OUTPUT_HANDLE, buf, n);
  }
  // Linux PTY masters report EIO, rather than EOF, when the last slave closes.
  return writable ? 0 : 1;
}

#ifdef _WIN32
static DWORD WINAPI copy_output(void *arg) {
  return (DWORD)copy_output_stream(arg);
}

// Quote each UTF-8 argv element using the Windows CRT command-line rules.
// Doubling backslashes before quotes also preserves trailing backslashes.
static WCHAR *make_command_line(moonbit_bytes_t *args) {
  int argc = Moonbit_array_length(args);
  size_t capacity = 1;
  for (int i = 0; i < argc; i++) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                               (const char *)args[i], -1, NULL, 0);
    if (!n)
      return NULL;
    capacity += 2 * (size_t)n + 3;
  }
  // CreateProcessW limits its command line to 32767 UTF-16 code units.
  if (capacity > 32767) {
    SetLastError(ERROR_BAD_LENGTH);
    return NULL;
  }
  WCHAR *command = malloc(capacity * sizeof(WCHAR));
  if (!command) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  WCHAR *p = command;
  for (int i = 0; i < argc; i++) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                               (const char *)args[i], -1, NULL, 0);
    WCHAR *arg = malloc((size_t)n * sizeof(WCHAR));
    if (!arg) {
      free(command);
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      return NULL;
    }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                            (const char *)args[i], -1, arg, n)) {
      free(arg);
      free(command);
      return NULL;
    }
    if (i) *p++ = L' ';
    *p++ = L'"';
    const WCHAR *s = arg;
    for (;;) {
      size_t slashes = 0;
      while (*s == L'\\') {
        slashes++;
        s++;
      }
      size_t copies = (*s == L'"' || !*s) ? 2 * slashes : slashes;
      while (copies--) *p++ = L'\\';
      if (!*s)
        break;
      if (*s == L'"') *p++ = L'\\';
      *p++ = *s++;
    }
    *p++ = L'"';
    free(arg);
  }
  *p = 0;
  return command;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_async_test_programs_pty_run(moonbit_bytes_t *args) {
  HANDLE input_read = NULL, input = NULL, output = NULL, output_write = NULL;
  HANDLE copier = NULL, job = NULL;
  HPCON console = NULL;
  PROCESS_INFORMATION child = {0};
  STARTUPINFOEXW startup = {0};
  int attributes_initialized = 0;
  DWORD code = 1, copy_code = 0;
  // CreateProcessW may modify its command-line buffer.
  WCHAR *command_line = make_command_line(args);
  if (!command_line)
    goto fail;

  // If the test times out and kills this harness, ttyd must die as well.
  job = CreateJobObjectW(NULL, NULL);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                      &limits, sizeof(limits)))
    goto fail;
  if (!CreatePipe(&input_read, &input, NULL, 0) ||
      !CreatePipe(&output, &output_write, NULL, 0))
    goto fail;
  COORD size = {80, 24};
  if (FAILED(CreatePseudoConsole(size, input_read, output_write, 0, &console)))
    goto fail;
  CloseHandle(input_read);
  input_read = NULL;
  CloseHandle(output_write);
  output_write = NULL;
  copier = CreateThread(NULL, 0, copy_output, output, 0, NULL);
  if (!copier)
    goto fail;

  SIZE_T attr_size = 0;
  InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
  startup.StartupInfo.cb = sizeof(startup);
  // Do not inherit the harness's redirected stdio into the console child.
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.lpAttributeList = malloc(attr_size);
  if (!startup.lpAttributeList ||
      !InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attr_size))
    goto fail;
  attributes_initialized = 1;
  if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0,
        PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, console, sizeof(HPCON), NULL, NULL))
    goto fail;
  // @process starts us in a new process group, which disables Ctrl-C. Clear
  // that inherited flag before creating the child in its own pseudo console.
  if (!SetConsoleCtrlHandler(NULL, FALSE))
    goto fail;
  if (!CreateProcessW(NULL, command_line, NULL, NULL, FALSE,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED, NULL, NULL,
        &startup.StartupInfo, &child))
    goto fail;
  if (!AssignProcessToJobObject(job, child.hProcess) ||
      ResumeThread(child.hThread) == (DWORD)-1)
    goto fail;
  if (!read_commands(console, input))
    goto fail;
  if (WaitForSingleObject(child.hProcess, INFINITE) != WAIT_OBJECT_0 ||
      !GetExitCodeProcess(child.hProcess, &code))
    goto fail;
  goto cleanup;

fail:
  fprintf(stderr, "pty failed (Windows error %lu)\n", GetLastError());
  code = 1;
  if (child.hProcess) {
    TerminateProcess(child.hProcess, 1);
    WaitForSingleObject(child.hProcess, INFINITE);
  }
cleanup:
  if (attributes_initialized)
    DeleteProcThreadAttributeList(startup.lpAttributeList);
  free(startup.lpAttributeList);
  free(command_line);
  if (input_read) CloseHandle(input_read);
  if (output_write) CloseHandle(output_write);
  if (input) CloseHandle(input);
  if (!copier && output) {
    CloseHandle(output);
    output = NULL;
  }
  if (console) ClosePseudoConsole(console);
  if (copier) {
    WaitForSingleObject(copier, INFINITE);
    GetExitCodeThread(copier, &copy_code);
    CloseHandle(copier);
  }
  if (output) CloseHandle(output);
  if (child.hThread) CloseHandle(child.hThread);
  if (child.hProcess) CloseHandle(child.hProcess);
  if (job) CloseHandle(job);
  return (int32_t)(copy_code ? 1 : code);
}
#else
struct output_copy {
  int master;
  int code;
};

static void *copy_output(void *arg) {
  struct output_copy *copy = arg;
  copy->code = copy_output_stream(copy->master);
  return NULL;
}

static int wait_child(pid_t child, int *status) {
  pid_t result;
  do {
    result = waitpid(child, status, 0);
  } while (result < 0 && errno == EINTR);
  return result == child;
}

static void child_failed(int error_pipe) {
  int error = errno;
  write_all(error_pipe, &error, sizeof(error));
  _exit(127);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_async_test_programs_pty_run(moonbit_bytes_t *args) {
  int master = -1, slave = -1, errors[2] = {-1, -1};
  pid_t child = -1;
  pthread_t copier;
  int copying = 0, status = 0, code = 1;
  struct output_copy copy = {-1, 0};
  int argc = Moonbit_array_length(args);
  char **argv = calloc((size_t)argc + 1, sizeof(char *));
  if (!argv)
    goto fail;
  for (int i = 0; i < argc; i++)
    argv[i] = (char *)args[i];
  // A closed output pipe must not interrupt child cleanup or output draining.
  signal(SIGPIPE, SIG_IGN);
  signal(SIGCHLD, SIG_DFL);
  master = posix_openpt(O_RDWR | O_NOCTTY);
  if (master < 0 || grantpt(master) < 0 || unlockpt(master) < 0)
    goto fail;
  char *name = ptsname(master);
  if (!name || (slave = open(name, O_RDWR | O_NOCTTY)) < 0 ||
      !resize_terminal(master, 24, 80) || pipe(errors) < 0 ||
      fcntl(errors[1], F_SETFD, FD_CLOEXEC) < 0)
    goto fail;
  child = fork();
  if (child < 0)
    goto fail;
  if (child == 0) {
    close(errors[0]);
    close(master);
    sigset_t empty;
    sigemptyset(&empty);
    if (sigprocmask(SIG_SETMASK, &empty, NULL) < 0)
      child_failed(errors[1]);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGQUIT, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0 ||
        tcsetpgrp(slave, getpgrp()) < 0)
      child_failed(errors[1]);
    int null = open("/dev/null", O_RDWR);
    if (null < 0)
      child_failed(errors[1]);
    for (int fd = 0; fd < 3; fd++) {
      if (dup2(null, fd) < 0)
        child_failed(errors[1]);
    }
    if (null > 2) close(null);
    close(slave);
    execvp(argv[0], argv);
    child_failed(errors[1]);
  }
  close(errors[1]);
  errors[1] = -1;
  int child_error = 0;
  size_t n;
  if (!read_some(errors[0], &child_error, sizeof(child_error), &n))
    goto fail;
  if (n) {
    errno = child_error;
    goto fail;
  }
  close(errors[0]);
  errors[0] = -1;
  // Keep this slave anchor until child exit: all child stdio is /dev/null,
  // so ttyd has to open /dev/tty before it owns a slave descriptor itself.
  copy.master = master;
  int error = pthread_create(&copier, NULL, copy_output, &copy);
  if (error) {
    errno = error;
    goto fail;
  }
  copying = 1;
  if (!read_commands(master, master)) {
    fprintf(stderr, "pty: invalid command or terminal I/O failure\n");
    goto terminate;
  }
  if (!wait_child(child, &status))
    goto fail;
  child = -1;
  code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
  goto cleanup;

fail:
  perror("pty");
terminate:
  if (child > 0) {
    // The child owns a fresh session/process group, separate from the harness.
    kill(-child, SIGKILL);
    kill(child, SIGKILL);
    wait_child(child, &status);
  }
cleanup:
  if (errors[0] >= 0) close(errors[0]);
  if (errors[1] >= 0) close(errors[1]);
  // Closing the anchor after child exit lets the master report EOF/EIO.
  if (slave >= 0) close(slave);
  if (copying) pthread_join(copier, NULL);
  if (master >= 0) close(master);
  free(argv);
  return copy.code ? 1 : code;
}
#endif
