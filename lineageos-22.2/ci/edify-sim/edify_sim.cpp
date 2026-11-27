// Runs an OTA updater-script through the real AOSP edify interpreter (libedify,
// bootable/deprecated-ota/edify) with stub functions, so the installer logic can be
// tested on a PC against fake partition tables. Nothing is written anywhere except
// a text log: every "write" function only records what it would have done.
//
// Usage: edify_sim SCRIPT LOGFILE
// Environment: SIM_TZ_OK=0 makes axon7.verify_trustzone fail; SIM_DEVICE is the
// value of ro.product.device; run_program really runs the program (the layout
// script with AXON7_* overrides from the environment).
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "edify/expr.h"

static FILE* simlog;

static bool Args(State* s, const std::vector<std::unique_ptr<Expr>>& argv, std::vector<std::string>* a) {
  return ReadArgs(s, argv, a);
}

static Value* UiPrint(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a)) return nullptr;
  for (auto& x : a) fprintf(simlog, "UI: %s\n", x.c_str());
  return StringValue(a.empty() ? "" : a[0]);
}

static Value* RunProgram(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a) || a.empty()) return nullptr;
  std::string prog = a[0];
  // /tmp/install/bin/NAME -> the real script in SIM_BIN (extracted from the zip by the test)
  const char* bin = getenv("SIM_BIN");
  size_t p = prog.rfind('/');
  if (bin && p != std::string::npos && prog.compare(0, 17, "/tmp/install/bin/") == 0)
    prog = std::string(bin) + "/" + prog.substr(p + 1);
  fprintf(simlog, "RUN: %s\n", a[0].c_str());
  if (a[0].find("backuptool.sh") != std::string::npos) return StringValue("0");  // addon.d, not under test
  pid_t pid = fork();
  if (pid == 0) {
    std::vector<char*> av;
    av.push_back(const_cast<char*>("sh"));
    av.push_back(const_cast<char*>(prog.c_str()));
    for (size_t i = 1; i < a.size(); i++) av.push_back(const_cast<char*>(a[i].c_str()));
    av.push_back(nullptr);
    execv("/bin/sh", av.data());
    _exit(127);
  }
  int st = 0;
  waitpid(pid, &st, 0);
  int rc = WIFEXITED(st) ? WEXITSTATUS(st) : 255;
  fprintf(simlog, "EXIT: %d\n", rc);
  return StringValue(std::to_string(rc));
}

static Value* ReadFile(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a) || a.size() != 1) return nullptr;
  const char* out = getenv("AXON7_OUT");
  std::string path = a[0];
  if (out && path.compare(0, 5, "/tmp/") == 0) path = std::string(out) + "/" + path.substr(5);
  std::ifstream f(path);
  if (!f) return StringValue("");
  std::stringstream ss;
  ss << f.rdbuf();
  return StringValue(ss.str());
}

static Value* FileGetprop(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a) || a.size() != 2) return nullptr;
  const char* out = getenv("AXON7_OUT");
  std::string path = a[0];
  if (out && path.compare(0, 5, "/tmp/") == 0) path = std::string(out) + "/" + path.substr(5);
  std::ifstream f(path);
  std::string line;
  while (std::getline(f, line)) {
    size_t e = line.find('=');
    if (e != std::string::npos && line.substr(0, e) == a[1]) return StringValue(line.substr(e + 1));
  }
  return StringValue("");
}

static Value* GetProp(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a) || a.size() != 1) return nullptr;
  const char* d = getenv("SIM_DEVICE");
  if (a[0] == "ro.product.device" || a[0] == "ro.build.product") return StringValue(d ? d : "ailsa_ii");
  return StringValue("");
}

static Value* VerifyTz(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a)) return nullptr;
  const char* ok = getenv("SIM_TZ_OK");
  return StringValue(ok && std::string(ok) == "0" ? "0" : "1");
}

// package_extract_file("x") returns a blob, package_extract_file("x", "/dev/...") writes it.
static Value* ExtractFile(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a) || a.empty()) return nullptr;
  if (a.size() == 1) return new Value(Value::Type::BLOB, a[0]);
  fprintf(simlog, "WRITE: %s -> %s\n", a[0].c_str(), a[1].c_str());
  return StringValue("t");
}

static Value* BlockImageUpdate(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::unique_ptr<Value>> v;
  if (!ReadValueArgs(s, argv, &v) || v.size() != 4) return nullptr;
  fprintf(simlog, "WRITE: block_image_update %s <- %s %s (transfer list %s)\n", v[0]->data.c_str(),
          v[2]->data.c_str(), v[3]->data.c_str(), v[1]->data.c_str());
  return StringValue("t");
}

static Value* Quiet(const char*, State* s, const std::vector<std::unique_ptr<Expr>>& argv) {
  std::vector<std::string> a;
  if (!Args(s, argv, &a)) return nullptr;
  return StringValue("t");
}

int main(int argc, char** argv) {
  if (argc != 3) { fprintf(stderr, "usage: %s SCRIPT LOG\n", argv[0]); return 2; }
  std::ifstream f(argv[1]);
  std::stringstream ss;
  ss << f.rdbuf();
  std::string script = ss.str();
  simlog = fopen(argv[2], "w");
  RegisterBuiltins();
  RegisterFunction("ui_print", UiPrint);
  RegisterFunction("run_program", RunProgram);
  RegisterFunction("read_file", ReadFile);
  RegisterFunction("file_getprop", FileGetprop);
  RegisterFunction("getprop", GetProp);
  RegisterFunction("axon7.verify_trustzone", VerifyTz);
  RegisterFunction("package_extract_file", ExtractFile);
  RegisterFunction("block_image_update", BlockImageUpdate);
  for (const char* n : {"package_extract_dir", "set_metadata_recursive", "show_progress", "set_progress"})
    RegisterFunction(n, Quiet);
  std::unique_ptr<Expr> root;
  int errors = 0;
  ParseString(script, &root, &errors);
  if (errors > 0 || !root) { fprintf(simlog, "PARSE-ERRORS: %d\n", errors); fclose(simlog); return 4; }
  State state(script, nullptr);
  std::string result;
  bool ok = Evaluate(&state, root, &result);
  if (!ok) { fprintf(simlog, "ABORT: %s\n", state.errmsg.c_str()); fclose(simlog); return 3; }
  fprintf(simlog, "DONE\n");
  fclose(simlog);
  return 0;
}
