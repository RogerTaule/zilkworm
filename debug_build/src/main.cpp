#include "./include/cppextern.hpp"
#include <cstdio>
#include <string>
#include "./include/semihosting.hpp"

// Keep a static buffer big enough for your JSON payloads.
static char JSON_BUF[64 * 1024];

int main(int argc, char *argv[])
{
    // 1) Read n (uint32 decimal) from stdin
    std::uint32_t n = 0;
    if (!sh::read_u32_from_stdin(n))
    {
        sys_println("Could not read file size from stdin");
        for (;;)
        {
        } // parse error -> park
    }

    // 2) Read exactly n bytes of JSON
    if (static_cast<std::size_t>(n) >= sizeof(JSON_BUF))
    {
        sys_println("File Too large for JSON_BUF");
        for (;;)
        {
        } // too large -> park
    }

    if (!sh::read_exact(JSON_BUF, static_cast<std::size_t>(n)))
    {
        sys_println("Unexpected EOF");
        for (;;)
        {
        } // unexpected EOF -> park
    }

    JSON_BUF[n] = '\0'; // null-terminate for convenience

    std::string jsonStr(JSON_BUF, JSON_BUF + n);
    sys_println("The string read:");
    sys_println(jsonStr.c_str());
    const uint64_t res = sample_run_wrapped(n, jsonStr);
    char buf[64];
    std::snprintf(buf, sizeof(buf), "State transition result: %llu", res);
    sys_println(buf);
    // printf("State transition result: %d\n", res);
    while (1)
    {
    } // loop indefinitely (no OS to return to)
    // return 0;   // Don't
}