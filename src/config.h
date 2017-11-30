#define  IMHT 256                //image height
#define  IMWD 256                //image width
#define  INPUT "256x256.pgm"
#define  OUTPUT "testout"
#if ((IMHT%8 != 0) || (IMHT != IMWD)) 
  #error "Image not allowed."
#endif
#define  noOfThreads 2			  //Our implementation requires that this must be 2^n
#define  debugMode 0
#define  generateOnBoard 0		//If true, will ignore input name
#define  printAllImages 0


