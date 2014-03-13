/* This file is meant to provide a naive .exe
   implementation of echo for shelling out in Julia on
   Windows, but with LF line endings instead of CRLF */
#include <stdio.h>
#include <fcntl.h>
int main(int argc, char *argv[])
{
    /* avoid pesky conversion of \n to \r\n */
    setmode(fileno(stdout), O_BINARY);
    int i;
    for (i = 1; i < argc-1; i++)
        printf("%s ", argv[i]);

    printf("%s\n", argv[argc-1]);
    return 0;
}
