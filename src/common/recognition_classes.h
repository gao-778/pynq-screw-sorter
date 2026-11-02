#ifndef RECOGNITION_CLASSES_H
#define RECOGNITION_CLASSES_H


#define REC_CLASS_COUNT 18U
#define REC_SCREW_CLASS_COUNT 15U
#define REC_CLASS_INVALID 31U
static const char *recognition_class_name(unsigned id){
 static const char *names[REC_CLASS_COUNT]={"M3_5","M3_4","M3_1","M4_5","M4_3","M4_1","M5_5","M5_4","M5_1","M3_2","M3_3","M4_2","M4_4","M5_2","M5_3","NUT_L","NUT_M","NUT_S"};
 return id<REC_CLASS_COUNT?names[id]:"UNKNOWN";
}
static unsigned recognition_number(unsigned id){
 static const unsigned numbers[REC_CLASS_COUNT]={5,4,1,10,8,6,15,14,11,2,3,7,9,12,13,16,17,18};
 return id<REC_CLASS_COUNT?numbers[id]:0U;
}
static const char *recognition_short_name(unsigned id){
 static const char *names[REC_CLASS_COUNT]={"M35","M34","M31","M45","M43","M41","M55","M54","M51","M32","M33","M42","M44","M52","M53","N_L","N_M","N_S"};
 return id<REC_CLASS_COUNT?names[id]:"?";
}
static unsigned recognition_id_from_number(unsigned number){
 for(unsigned id=0;id<REC_CLASS_COUNT;++id)if(recognition_number(id)==number)return id;
 return REC_CLASS_INVALID;
}
static unsigned recognition_word_class(unsigned word){return (word&15U)|((word>>12)&16U);}
static unsigned recognition_selection_class(unsigned word){return ((word>>4)&15U)|((word>>7)&16U);}
static unsigned recognition_pickable(unsigned id){return id<REC_SCREW_CLASS_COUNT;}
#endif
