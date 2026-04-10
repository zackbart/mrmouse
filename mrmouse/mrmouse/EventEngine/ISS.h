#ifndef ISS_h
#define ISS_h

#include <stdbool.h>

bool iss_init(void);
void iss_destroy(void);

typedef enum {
    ISSDirectionLeft = 0,
    ISSDirectionRight = 1
} ISSDirection;

typedef struct {
    unsigned int currentIndex;
    unsigned int spaceCount;
} ISSSpaceInfo;

bool iss_switch(ISSDirection direction);
bool iss_get_space_info(ISSSpaceInfo *info);
bool iss_can_move(ISSSpaceInfo info, ISSDirection direction);

#endif /* ISS_h */