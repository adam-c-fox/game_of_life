#define  IMHT 512                  //image height
#define  IMWD 512                //image width
#define  INPUT "512x512.pgm"
#define  OUTPUT "testout"
#if IMHT%8 != 0
  #error "WHAT ARE YOU DOING?"
#endif
#define  noOfThreads 8			  //Our implementation requires that this must be 2^n
#define  debugMode 0


