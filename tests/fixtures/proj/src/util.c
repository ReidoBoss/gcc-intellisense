#include <stdio.h>
#include "proj.h"

int proj_add(int a, int b) {
    return a + b;
}

void proj_greet(const char *who) {
    printf("hello, %s\n", who);
}
