/**
 * This is an implementation of fastCDC
 * The origin paper is Wen Xia, Yukun Zhou, Hong Jiang, Dan Feng, Yu Hua, Yuchong Hu, Yucheng Zhang, Qing Liu, "FastCDC: a Fast and Efficient Content-Defined Chunking Approach for Data Deduplication", in Proceedings of USENIX Annual Technical Conference (USENIX ATC'16), Denver, CO, USA, June 22–24, 2016, pages: 101-114
 * and Wen Xia, Xiangyu Zou, Yukun Zhou, Hong Jiang, Chuanyi Liu, Dan Feng, Yu Hua, Yuchong Hu, Yucheng Zhang, "The Design of Fast Content-Defined Chunking for Data Deduplication based Storage Systems", IEEE Transactions on Parallel and Distributed Systems (TPDS), 2020
 *
 */ 

#include <openssl/md5.h>
#include <openssl/sha.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <zlib.h>
#include "uthash.h"

// predefined Gear Mask
extern uint64_t GEARv2[256];

#define SymbolCount 256
#define SeedLength 64
#define CacheSize 1024 * 1024 * 1024

#define ORIGIN_CDC 1
#define ROLLING_2Bytes 2
#define NORMALIZED_CDC 3
#define NORMALIZED_2Bytes 4

// Rolling2Bytes Mask
extern uint32_t FING_GEAR_08KB_ls;
extern uint32_t FING_GEAR_02KB_ls;
extern uint32_t FING_GEAR_32KB_ls;

extern uint64_t LEARv2[256];

extern uint64_t FING_GEAR_08KB_ls_64;
extern uint64_t FING_GEAR_02KB_ls_64;
extern uint64_t FING_GEAR_32KB_ls_64;
extern uint64_t FING_GEAR_08KB_64;

extern uint64_t FING_GEAR_02KB_64;
extern uint64_t FING_GEAR_32KB_64;

// global variants
extern struct timeval tmStart, tmEnd;
extern struct chunk_info *users;

extern float totalTm;
extern int chunk_dist[30];
extern uint32_t g_global_matrix[SymbolCount];
extern uint32_t g_global_matrix_left[SymbolCount];
extern uint32_t expectCS;
extern uint32_t Mask_15;
extern uint32_t Mask_11;
extern uint64_t Mask_11_64, Mask_15_64;

extern uint32_t MinSize;
extern uint32_t MinSize_divide_by_2;
extern uint32_t MaxSize;
extern int sameCount;
extern int tmpCount;
extern int smalChkCnt;

// init function
void fastCDC_init(void);

extern int (*chunking) (unsigned char*p, int n);

// origin fastcdc function
int cdc_origin_64(unsigned char *p, int n);

// fastcdc with once rolling 2 bytes 
int rolling_data_2byes_64(unsigned char *p, int n);

// normalized fastcdc
int normalized_chunking_64(unsigned char *p, int n);

// normalized fastcdc with once rolling 2 bytes
int normalized_chunking_2byes_64(unsigned char *p, int n);
