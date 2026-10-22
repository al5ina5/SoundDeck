#import "../Shared/SDIdentity.h"
#include <stdio.h>
extern int proc_pidpath(int,void *,uint32_t);
extern int proc_pidinfo(int,int,uint64_t,void *,int);
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=2) return 2; pid_t pid=atoi(argv[1]),owner=SDResponsiblePID(pid); char path[4096]={0};
    if(owner>0) proc_pidpath(owner,path,sizeof(path));
    uint64_t coalition[5]={0}; int bytes=proc_pidinfo(pid,20,0,coalition,sizeof(coalition));
    printf("pid=%d responsible=%d path=%s coalitionBytes=%d resource=%llu jetsam=%llu\n",pid,owner,path,bytes,coalition[0],coalition[1]); return 0;
} }
