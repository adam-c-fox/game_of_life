#define  IMHT 1472                  //image height
#define  IMWD 1472                //image width
#define  INPUT "64x64.pgm"
#define  OUTPUT "testout"
#if IMHT%8 != 0
  #error "WHAT ARE YOU DOING?"
#endif
#define  noOfThreads 2			  //Our implementation requires that this must be 2^n
#define  debugMode 0
#define  generateOnBoard 1		//If true, will ignore input name
#define  printAllImages 1


