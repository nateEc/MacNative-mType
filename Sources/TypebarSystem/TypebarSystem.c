#include "TypebarSystem.h"
#include <sys/file.h>

int typebar_file_lock(int descriptor, int operation) {
    return flock(descriptor, operation);
}
