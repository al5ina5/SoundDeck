#import "../Shared/SDProtocol.h"
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x); return 1; } } while(0)
int main(int argc,char **argv) { @autoreleasepool {
    if(argc==3) {
        for(int i=0;i<30;i++) { if(!SDUpdatePrefs(@{@"apps":@{@(argv[2]):@{@"gain":@(i/100.)}}},nil)) return 1; usleep(1000); }
        return 0;
    }
    NSDictionary *s=SDSanitizePrefs((id)@[@1]); CHECK([s[@"mixing"] boolValue]); CHECK([s[@"apps"] count]==0);
    s=SDSanitizePrefs(@{@"apps":@{@"invalid/id":@{},@"test.a":@{@"gain":@3,@"muted":@YES},@"test.b":@[]},@"appearance":@99});
    CHECK([s[@"apps"] count]==1); CHECK([s[@"apps"][@"test.a"][@"gain"] doubleValue]==1); CHECK([s[@"appearance"] intValue]==2);
    uint64_t config=SDConfig(@{@"mixing":@YES},@{@"gain":@.2,@"muted":@YES});
    CHECK((config&1023)==200); CHECK(config&(1ULL<<10)); CHECK(config&(1ULL<<11)); CHECK(config&(1ULL<<12));
    uint64_t state=SDClientState(YES,1,800,10000,8000);
    CHECK(SDFresh(state)); CHECK(((state>>4)&1023)==800); CHECK(((state>>14)&65535)==10000); CHECK(((state>>30)&65535)==8000);
    CHECK(SDWritePrefs(@{},nil));
    pid_t a,b; char *argsA[]={argv[0],"child","test.a",NULL}; char *argsB[]={argv[0],"child","test.b",NULL};
    CHECK(!posix_spawn(&a,argv[0],NULL,NULL,argsA,environ)); CHECK(!posix_spawn(&b,argv[0],NULL,NULL,argsB,environ));
    int ra,rb; waitpid(a,&ra,0); waitpid(b,&rb,0); CHECK(ra==0 && rb==0);
    s=SDReadPrefs(); CHECK([s[@"apps"] count]==2);
    CHECK(fabs([s[@"apps"][@"test.a"][@"gain"] doubleValue]-.29)<1e-6);
    CHECK(fabs([s[@"apps"][@"test.b"][@"gain"] doubleValue]-.29)<1e-6);
    CHECK(SDUpdatePrefs(@{@"apps":@{@"test.a":@{@"muted":@YES}}},nil));
    CHECK([SDReadPrefs()[@"apps"][@"test.a"][@"muted"] boolValue]);
    CHECK(fabs([SDReadPrefs()[@"apps"][@"test.a"][@"gain"] doubleValue]-.29)<1e-6);
    puts("PASS malformed preference validation, IPC packing, 60 concurrent transactions, per-field merge"); return 0;
} }
