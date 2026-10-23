/*
 * Copyright 2025 International Digital Economy Academy
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

// Pseudo console helpers, used by the Windows tests only.
//
// A process can only attach to a console that some process is attached to,
// so a placeholder child is started on the pseudo console and the test
// process attaches to the console of that child. CONIN$/CONOUT$ then refer
// to the pseudo console, input is driven by writing VT sequences to its input
// pipe and the window is resized with `ResizePseudoConsole`.
//
// There is one console per process, so there is one pseudo console at a time.

// Provided by `src/internal/event_loop/signal.c`.
int moonbitlang_async_set_console_control_handler(int32_t add);

// Attaching to a console resets the console control handlers of the process,
// including the one the event loop registered and removes when it exits.
// Tests run inside the event loop, so register it again.
static
void restore_console_control_handler() {
  moonbitlang_async_set_console_control_handler(1);
}

static struct {
  HPCON console;
  HANDLE input;
  HANDLE output;
  HANDLE drain_thread;
  PROCESS_INFORMATION child;
} test_console;

// The pseudo console blocks once its output pipe is full, keep it empty.
static
DWORD WINAPI drain_output(void *output) {
  char buf[4096];
  DWORD n;
  while (ReadFile((HANDLE)output, buf, sizeof(buf), &n, NULL) && n > 0) {}
  return 0;
}

MOONBIT_FFI_EXPORT
void moonbitlang_async_tty_test_console_close() {
  // Detach first: closing the pseudo console sends `CTRL_CLOSE_EVENT`
  // to every process attached to it.
  FreeConsole();
  // back to the console the test runner gave us, if any
  AttachConsole(ATTACH_PARENT_PROCESS);
  restore_console_control_handler();

  if (test_console.console) {
    ClosePseudoConsole(test_console.console);
    test_console.console = NULL;
  }
  if (test_console.child.hProcess) {
    TerminateProcess(test_console.child.hProcess, 0);
    WaitForSingleObject(test_console.child.hProcess, INFINITE);
    CloseHandle(test_console.child.hProcess);
    CloseHandle(test_console.child.hThread);
    memset(&test_console.child, 0, sizeof(test_console.child));
  }
  if (test_console.input) {
    CloseHandle(test_console.input);
    test_console.input = NULL;
  }
  if (test_console.drain_thread) {
    // The pseudo console lives on while the test still holds handles to it
    // (a `Tty` is never closed), so the pipe may never break.
    while (WaitForSingleObject(test_console.drain_thread, 10) == WAIT_TIMEOUT)
      CancelSynchronousIo(test_console.drain_thread);
    CloseHandle(test_console.drain_thread);
    test_console.drain_thread = NULL;
  }
  if (test_console.output) {
    CloseHandle(test_console.output);
    test_console.output = NULL;
  }
}

// Create a pseudo console of the given size and attach the process to it.
// Return `0` on success, `-1` on failure.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_test_console_open(int32_t rows, int32_t cols) {
  HANDLE input_read = NULL, output_write = NULL;
  if (!CreatePipe(&input_read, &test_console.input, NULL, 0))
    goto fail;
  if (!CreatePipe(&test_console.output, &output_write, NULL, 0))
    goto fail;

  COORD size = { (SHORT)cols, (SHORT)rows };
  if (FAILED(CreatePseudoConsole(size, input_read, output_write, 0, &test_console.console)))
    goto fail;
  CloseHandle(input_read);
  input_read = NULL;
  CloseHandle(output_write);
  output_write = NULL;

  test_console.drain_thread = CreateThread(NULL, 0, drain_output, test_console.output, 0, NULL);
  if (!test_console.drain_thread)
    goto fail;

  SIZE_T attr_size = 0;
  InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
  STARTUPINFOEXW startup;
  memset(&startup, 0, sizeof(startup));
  startup.StartupInfo.cb = sizeof(startup);
  // Without this the child inherits the redirected stdio of the test runner
  // instead of using the pseudo console.
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attr_size);
  if (!startup.lpAttributeList)
    goto fail;
  if (
    !InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attr_size)
    || !UpdateProcThreadAttribute(
      startup.lpAttributeList,
      0,
      PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
      test_console.console,
      sizeof(HPCON),
      NULL,
      NULL
    )
  ) {
    free(startup.lpAttributeList);
    goto fail;
  }

  // A placeholder that keeps the console alive without reading its input.
  WCHAR command[] = L"ping.exe -n 3600 127.0.0.1";
  BOOL created = CreateProcessW(
    NULL,
    command,
    NULL,
    NULL,
    FALSE,
    EXTENDED_STARTUPINFO_PRESENT,
    NULL,
    NULL,
    &startup.StartupInfo,
    &test_console.child
  );
  DeleteProcThreadAttributeList(startup.lpAttributeList);
  free(startup.lpAttributeList);
  if (!created)
    goto fail;

  FreeConsole();
  // The child may not have connected to the console yet.
  for (int i = 0; !AttachConsole(test_console.child.dwProcessId); ++i) {
    if (i >= 100)
      goto fail;
    Sleep(10);
  }
  restore_console_control_handler();
  return 0;

fail:
  if (input_read)
    CloseHandle(input_read);
  if (output_write)
    CloseHandle(output_write);
  moonbitlang_async_tty_test_console_close();
  return -1;
}

// Send `data` to the pseudo console as if typed in the terminal.
MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_test_console_input(moonbit_bytes_t data) {
  DWORD len = (DWORD)Moonbit_array_length(data);
  DWORD written = 0;
  if (!WriteFile(test_console.input, data, len, &written, NULL) || written != len)
    return -1;
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonbitlang_async_tty_test_console_resize(int32_t rows, int32_t cols) {
  COORD size = { (SHORT)cols, (SHORT)rows };
  return FAILED(ResizePseudoConsole(test_console.console, size)) ? -1 : 0;
}

#endif
