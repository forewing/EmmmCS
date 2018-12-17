#include "intr.h"
#include "../driver/kbd.h"

static u8* intr_args = (u8*)INDR_ADDR;

void intr(){
    switch(intr_args[0]){
        case 0: return;
        case 1: kbd_update(intr_args + 1); break;
        default: break;
    }
    // TODO: insert a mret instr here
    return;
}