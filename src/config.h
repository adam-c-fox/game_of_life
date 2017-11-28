#define  IMHT 16                  //image height
#define  IMWD 16                //image width
#define  INPUT "test.pgm"
#define  OUTPUT "testout"
#if IMHT%8 != 0
  #error "WHAT ARE YOU DOING?"
#endif
#define  noOfThreads 2			  //Our implementation requires that this must be 2^n
#define  debugMode 1
#define  generateOnBoard 0		//If true, will ignore input name
#define  printAllImages 0


