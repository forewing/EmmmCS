#include "intr.h"
#include "../driver/kbd.h"

static u8* intr_args = (u8*)INDR_ADDR;

void intr_init(){
    *((u32*) intr_args) = 0;
    // TODO: insert an instr to set the idtr to intr()'s address
}

void intr_open(){
    __asm__ ("ecall");
}

void intr_close(){
    __asm__ ("ebreak");
}

void intr(){
    switch(intr_args[0]){
        case 0: return;
        case 1: kbd_update(intr_args + 1); break;
        default: break;
    }
    intr_close();
    __asm__ ("mret");
    return;
}