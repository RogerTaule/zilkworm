#include "./include/cppextern.hpp"
#include <cstdio>
#include <string>
#include "./include/semihosting.hpp"

// Keep a static buffer big enough for your JSON payloads.
static char JSON_BUF[64 * 1024 * 1024];

int main(int argc, char *argv[])
{
    // Read the entire input at once using SYS_READ on stdin (fd=0)
    std::uint32_t n = 0;

    // Open a handle
    int h = sh::open_tty_read();
    if (h < 0)
    {
        sys_println("Failed to open tty_read");
        for (;;)
        {
        }
    }
    // int h = 0;

    // First, read the number using a small buffer
    char num_buf[32];
    std::size_t num_len = sh::read_handle(h, num_buf, sizeof(num_buf));

    std::size_t i = 0;
    bool is_test = 0;

    //Skip blanks
    while (i < num_len && (num_buf[i] == ' ' || num_buf[i] == '\t' ||
                           num_buf[i] == '\r' || num_buf[i] == '\n'))
    {
        i++;
    }
    // Read is_test
    if(i < num_len && num_buf[i] == '0' || num_buf[i] == '1'){
        is_test = num_buf[i] - '0';
        i++;
        // Skip blanks
        while (i < num_len && (num_buf[i] == ' ' || num_buf[i] == '\t' ||
                           num_buf[i] == '\r' || num_buf[i] == '\n'))
        {
            i++;
        }
    }

    // Read n
    while (i < num_len && num_buf[i] >= '0' && num_buf[i] <= '9')
    {
        n = n * 10 + (num_buf[i] - '0');
        i++;
    }

    // Now read the JSON data
    if (n >= sizeof(JSON_BUF))
    {
        sys_println("File too large for JSON_BUF");
        for (;;)
        {
        }
    }

    // Skip blanks
    while (i < num_len && (num_buf[i] == ' ' || num_buf[i] == '\t' ||
                           num_buf[i] == '\r' || num_buf[i] == '\n'))
    {
        i++;
    }

    // Copy any leftover bytes from num_buf
    std::size_t copied = 0;
    while (i < num_len && copied < n)
    {
        JSON_BUF[copied++] = num_buf[i++];
    }

    // Read the rest directly
    std::size_t got = sh::read_exact_handle(h, JSON_BUF + copied, n - copied);
    if (got == 0)
    {
        sys_println("Unexpected EOF");
        for (;;)
        {
        }
    }
    copied += got;

    // JSON_BUF[n] = '\0'; // null-terminate for convenience
    std::string jsonStr(JSON_BUF, JSON_BUF + n);
    char buf[64];
    std::snprintf(buf, sizeof(buf), "Input file read length: %zu", jsonStr.size());
    sys_println(buf);

    // sys_println(jsonStr.c_str());
    const uint64_t res = sample_run_wrapped(is_test, jsonStr);
    // char buf[64];
    std::snprintf(buf, sizeof(buf), "State transition result: %llu", res);
    sys_println(buf);
    // printf("State transition result: %d\n", res);
    while (1)
    {
    } // loop indefinitely (no OS to return to)
    // return 0;   // Don't
}