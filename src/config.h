#define  IMHT 64                  //image height
#define  IMWD 64                //image width
#define  INPUT "64x64.pgm"
#define  OUTPUT "testout"
#if IMHT%8 != 0
  #error "WHAT ARE YOU DOING?"
#endif
#define  noOfThreads 4			  //Our implementation requires that this must be 2^n
#define  debugMode 1
#define  generateOnBoard 0		//If true, will ignore input name
#define  printAllImages 0


