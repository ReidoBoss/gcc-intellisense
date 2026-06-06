#include <stdio.h>
#include "proj.h"

int main(void) {
    proj_greet("world");
    printf("magic = 0x%x\n", PROJ_MAGIC);
    printf("sum   = %d\n", proj_add(2, 3));
    return 0;
}
