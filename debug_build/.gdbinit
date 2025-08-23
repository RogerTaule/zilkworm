set confirm off
set pagination off
set disassemble-next-line on
target remote :1234
monitor system_reset
break _start
break __entry
break main
break main.cpp:12
continue
