/* Copyright 2026 International Digital Economy Academy
 * Licensed under the Apache License, Version 2.0.
 */

#ifdef _WIN32
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

// stdin: "input <byte count>\n" followed by that many bytes, or
//        "resize <rows> <cols>\n". Commands must not be interleaved.
// stdout: the unmodified ConPTY output stream (UTF-8 and VT sequences).
// stderr: "ok\n" after a resize, or an error diagnostic.
// Closing stdin finishes the script; the caller must also let the child exit.
// The child's exit code is propagated unchanged, including STATUS_CONTROL_C_EXIT.

static int write_all(HANDLE file, const void *data, DWORD size) {
  const char *p = data;
  while (size) {
    DWORD n;
    if (!WriteFile(file, p, size, &n, NULL) || n == 0)
      return 0;
    p += n;
    size -= n;
  }
  return 1;
}

static DWORD WINAPI copy_output(void *arg) {
  char buf[4096];
  DWORD n;
  int writable = 1;
  while (ReadFile(arg, buf, sizeof(buf), &n, NULL) && n) {
    // Keep draining even if the caller closes stdout: ClosePseudoConsole can
    // wait for this pipe on older Windows versions.
    if (writable)
      writable = write_all(GetStdHandle(STD_OUTPUT_HANDLE), buf, n);
  }
  return writable ? 0 : 1;
}

static int read_commands(HPCON console, HANDLE input) {
  HANDLE source = GetStdHandle(STD_INPUT_HANDLE);
  char header[80], buf[4096];
  for (;;) {
    DWORD n;
    size_t pos = 0;
    do {
      if (!ReadFile(source, header + pos, 1, &n, NULL) || n == 0)
        return pos == 0;
      if (++pos == sizeof(header))
        return 0;
    } while (header[pos - 1] != '\n');
    header[pos] = 0;
    unsigned int length, rows, cols;
    char extra;
    if (sscanf(header, "input %u %c", &length, &extra) == 1) {
      while (length) {
        DWORD count = length < sizeof(buf) ? length : sizeof(buf);
        if (!ReadFile(source, buf, count, &n, NULL) || n == 0 ||
            !write_all(input, buf, n))
          return 0;
        length -= n;
      }
    } else if (sscanf(header, "resize %u %u %c", &rows, &cols, &extra) == 2 &&
               rows > 0 && rows <= 32767 && cols > 0 && cols <= 32767) {
      COORD size = { (SHORT)cols, (SHORT)rows };
      if (FAILED(ResizePseudoConsole(console, size)) ||
          !write_all(GetStdHandle(STD_ERROR_HANDLE), "ok\n", 3))
        return 0;
    } else {
      return 0;
    }
  }
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_test_conpty_run(moonbit_string_t command) {
  HANDLE input_read = NULL, input = NULL, output = NULL, output_write = NULL;
  HANDLE copier = NULL, job = NULL;
  HPCON console = NULL;
  PROCESS_INFORMATION child = {0};
  STARTUPINFOEXW startup = {0};
  int attributes_initialized = 0;
  DWORD code = 1, copy_code = 0;
  // CreateProcessW may modify its command-line buffer.
  size_t command_size = (Moonbit_array_length(command) + 1) * sizeof(WCHAR);
  WCHAR *command_line = malloc(command_size);
  if (!command_line)
    goto fail;
  memcpy(command_line, command, command_size);

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
  fprintf(stderr, "conpty failed (Windows error %lu)\n", GetLastError());
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
#endif
