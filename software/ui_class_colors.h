#ifndef UI_CLASS_COLORS_H
#define UI_CLASS_COLORS_H
/* Presentation only: raw CNN class IDs, never display numbers or bin IDs.
 * CSR 0x54 stages one 27-bit word. The existing text-page commit at 0x1c
 * publishes text and colors together at vblank; its acknowledgement protects
 * both. Do not call the stage helper while a text commit is pending.
 * [1:0] mode (0 blue, 1 selected class red, 2 four-class palette)
 * [6:2] selected raw class; [11:7], [16:12], [21:17], [26:22] raw slots.
 * Raw ID 31 means unused. Palette slots are blue, teal, orange, purple.
 */
#define UI_CLASS_COLOR_REGISTER 0x54U
#define UI_CLASS_COLOR_UNUSED 31U
static unsigned ui_class_color_mode;
static unsigned ui_class_color_slots[4]={31U,31U,31U,31U};
static unsigned ui_class_color_written,ui_class_color_word;

static unsigned ui_class_colors_present(const AutoPickView *view,unsigned id){
    for(unsigned k=0;k<view->class_count && k<REC_CLASS_COUNT;++k)
        if(view->class_ids[k]==id && id<REC_CLASS_COUNT && view->counts[id])return 1U;
    return 0U;
}
static unsigned ui_class_colors_prepare(const AutoPickView *view){
    unsigned mode=!view->open?0U:view->mode==AUTO_PICK_CLASS_PICK?1U:
        view->mode==AUTO_PICK_SORT_ALL?2U:0U;
    if(mode!=ui_class_color_mode){
        for(unsigned k=0;k<4U;++k)ui_class_color_slots[k]=UI_CLASS_COLOR_UNUSED;
        ui_class_color_mode=mode;
    }
    if(!mode)return 0U;
    if(mode==2U && view->catalog_valid && !view->catalog_stale){
        /* Keep a present class in its slot. The catalog's two-new-frame
         * confirmation already rejects one-frame count changes; handoff or
         * stale snapshots must not release/reassign a color slot. */
        for(unsigned k=0;k<4U;++k)
            if(!ui_class_colors_present(view,ui_class_color_slots[k]))
                ui_class_color_slots[k]=UI_CLASS_COLOR_UNUSED;
        for(unsigned n=0;n<view->class_count && n<REC_CLASS_COUNT;++n){
            unsigned id=view->class_ids[n],present=0;
            if(id>=REC_CLASS_COUNT || !view->counts[id])continue;
            for(unsigned k=0;k<4U;++k)if(ui_class_color_slots[k]==id)present=1U;
            if(present)continue;
            for(unsigned k=0;k<4U;++k)if(ui_class_color_slots[k]==UI_CLASS_COLOR_UNUSED){
                ui_class_color_slots[k]=id;break;
            }
        }
    }
    unsigned selected=mode==1U && view->selected_class<REC_CLASS_COUNT?
        view->selected_class:UI_CLASS_COLOR_UNUSED;
    unsigned word=mode|(selected<<2);
    for(unsigned k=0;k<4U;++k)word|=ui_class_color_slots[k]<<(7U+5U*k);
    return word;
}
static unsigned ui_class_colors_style(unsigned id){
    static const unsigned styles[4]={12U,11U,14U,13U};
    for(unsigned k=0;k<4U;++k)if(ui_class_color_slots[k]==id)return styles[k];
    /* More than four visible classes use the ordinary blue fallback. This
     * changes no sort capacity, bin allocation or recognition class count. */
    return styles[0];
}
static unsigned ui_class_colors_changed(unsigned word){
    return !ui_class_color_written || ui_class_color_word!=word;
}
static void ui_class_colors_stage(unsigned word){
    if(ui_class_colors_changed(word)){
        ui_write(UI_CLASS_COLOR_REGISTER,word);
        ui_class_color_word=word;ui_class_color_written=1U;
    }
}
#endif
