// Optional WaveForms SDK bridge. Loads the user's installed DWF runtime at run time.
// capture = one acquisition; run = keep the device open and print one json line per acquisition until stdin closes
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <signal.h>
#ifdef _WIN32
#include <windows.h>
static HMODULE library;
static void *symbol(const char *name) { return (void *)GetProcAddress(library, name); }
static void pause_ms(int ms) { Sleep((DWORD)ms); }
static int input_closed(void) { DWORD n=0; return !PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE),NULL,0,NULL,&n,NULL); }
#else
#include <dlfcn.h>
#include <unistd.h>
#include <poll.h>
static void *library;
static void *symbol(const char *name) { return dlsym(library, name); }
static void pause_ms(int ms) { usleep((useconds_t)ms * 1000); }
static int input_closed(void) { struct pollfd p={0,POLLIN,0}; char b[64]; if(poll(&p,1,0)>0) { if(p.revents&(POLLHUP|POLLERR|POLLNVAL)) return 1; if(read(0,b,sizeof b)<=0) return 1; } return 0; }
#endif
#define LOAD(fn) do { *(void **)(&fn) = symbol("FDwf" #fn); if (!fn) { fprintf(stderr,"WaveForms SDK is missing FDwf%s\n",#fn); return 2; } } while (0)
#define OPTIONAL(fn) do { *(void **)(&fn) = symbol("FDwf" #fn); } while (0)
static int (*GetLastErrorMsg)(char *);
static int (*Enum)(int,int *);
static int (*EnumDeviceName)(int,char *);
static int (*DeviceOpen)(int,int *);
static int (*DeviceClose)(int);
static int (*EnumConfig)(int,int *);
static int (*EnumConfigInfo)(int,int,int *);
static int (*DeviceConfigOpen)(int,int,int *);
static int (*AnalogInFrequencySet)(int,double);
static int (*AnalogInFrequencyGet)(int,double *);
static int (*AnalogInBufferSizeInfo)(int,int *,int *);
static int (*AnalogInBufferSizeSet)(int,int);
static int (*AnalogInChannelEnableSet)(int,int,int);
static int (*AnalogInChannelRangeSet)(int,int,double);
static int (*AnalogInChannelRangeGet)(int,int,double *);
static int (*AnalogInTriggerSourceSet)(int,unsigned char);
static int (*AnalogInTriggerTypeSet)(int,int);
static int (*AnalogInTriggerChannelSet)(int,int);
static int (*AnalogInTriggerLevelSet)(int,double);
static int (*AnalogInTriggerConditionSet)(int,int);
static int (*AnalogInTriggerPositionSet)(int,double);
static int (*AnalogInTriggerAutoTimeoutSet)(int,double);
static int (*AnalogInConfigure)(int,int,int);
static int (*AnalogInStatus)(int,int,unsigned char *);
static int (*AnalogInStatusData)(int,int,double *,int);
static int (*DigitalInInternalClockInfo)(int,double *);
static int (*DigitalInDividerSet)(int,unsigned int);
static int (*DigitalInSampleFormatSet)(int,int);
static int (*DigitalInBufferSizeInfo)(int,int *);
static int (*DigitalInBufferSizeSet)(int,int);
static int (*DigitalInTriggerSourceSet)(int,unsigned char);
static int (*DigitalInTriggerSet)(int,unsigned int,unsigned int,unsigned int,unsigned int);
static int (*DigitalInTriggerPositionSet)(int,unsigned int);
static int (*DigitalInTriggerAutoTimeoutSet)(int,double);
static int (*DigitalInConfigure)(int,int,int);
static int (*DigitalInStatus)(int,int,unsigned char *);
static int (*DigitalInStatusData)(int,void *,int);
static volatile sig_atomic_t stopping;
static void on_signal(int s) { (void)s; stopping=1; }
static void error_message(const char *prefix) { char message[512]={0}; GetLastErrorMsg(message); fprintf(stderr,"%s: %s\n",prefix,message[0]?message:"WaveForms SDK call failed"); }
static void json_string(const char *s) { putchar('"'); for (;*s;s++) { unsigned char c=(unsigned char)*s; if (c=='"'||c=='\\') { putchar('\\');putchar(c); } else if(c>=32&&c<127) putchar(c); } putchar('"'); }
static int load_library(void) {
#ifdef _WIN32
 library=LoadLibraryA("dwf.dll");
#else
 library=dlopen("/Library/Frameworks/dwf.framework/dwf",RTLD_NOW|RTLD_LOCAL);
 if(!library) library=dlopen("/Applications/WaveForms.app/Contents/Frameworks/dwf.framework/dwf",RTLD_NOW|RTLD_LOCAL);
#endif
 if(!library) { fprintf(stderr,"Install Digilent WaveForms to use Analog Discovery capture.\n"); return 2; }
 LOAD(GetLastErrorMsg); LOAD(Enum); LOAD(EnumDeviceName); LOAD(DeviceOpen); LOAD(DeviceClose);
 LOAD(AnalogInFrequencySet);LOAD(AnalogInFrequencyGet);LOAD(AnalogInBufferSizeInfo);LOAD(AnalogInBufferSizeSet);LOAD(AnalogInChannelEnableSet);LOAD(AnalogInChannelRangeSet);LOAD(AnalogInTriggerSourceSet);LOAD(AnalogInTriggerTypeSet);LOAD(AnalogInTriggerChannelSet);LOAD(AnalogInTriggerLevelSet);LOAD(AnalogInTriggerConditionSet);LOAD(AnalogInTriggerAutoTimeoutSet);LOAD(AnalogInConfigure);LOAD(AnalogInStatus);LOAD(AnalogInStatusData);
 LOAD(DigitalInInternalClockInfo);LOAD(DigitalInDividerSet);LOAD(DigitalInSampleFormatSet);LOAD(DigitalInBufferSizeInfo);LOAD(DigitalInBufferSizeSet);LOAD(DigitalInTriggerSourceSet);LOAD(DigitalInTriggerSet);LOAD(DigitalInTriggerAutoTimeoutSet);LOAD(DigitalInConfigure);LOAD(DigitalInStatus);LOAD(DigitalInStatusData);
 OPTIONAL(EnumConfig);OPTIONAL(EnumConfigInfo);OPTIONAL(DeviceConfigOpen);OPTIONAL(AnalogInChannelRangeGet);OPTIONAL(AnalogInTriggerPositionSet);OPTIONAL(DigitalInTriggerPositionSet);
 return 0;
}
static int analysis(const unsigned char *bits,int count,double rate,double *period,double *high,double *duty) {
 int last_rise=-1,last_fall=-1,period_count=0,high_count=0;double period_sum=0,high_sum=0;
 for(int i=1;i<count;i++) {
  if(!bits[i-1]&&bits[i]) { if(last_rise>=0) {period_sum+=i-last_rise;period_count++;} last_rise=i; if(last_fall>=0&&last_fall<i) last_fall=-1; }
  if(bits[i-1]&&!bits[i]) {if(last_rise>=0&&last_fall<last_rise) {high_sum+=i-last_rise;high_count++;}last_fall=i;}
 }
 *period=period_count?period_sum/period_count/rate:0;
 *high=high_count?high_sum/high_count/rate:0;
 *duty=*period>0&&*high>0?100*(*high)/(*period):0;
 return period_count;
}
// request options: channels=0,3 trigger=0|none edge=rise|fall level=1.5 position=10 (% of window before trigger) mode=auto|normal range=5|50
typedef struct { int scope,count,list[16],trigger,falling,normal;double span,level,position,range; } Request;
static int parse(int argc,char **argv,Request *r) {
 memset(r,0,sizeof *r);r->level=1.5;r->position=10;r->range=50;
 if(argc<4) return 0;
 r->scope=strcmp(argv[2],"scope")==0;if(!r->scope&&strcmp(argv[2],"logic")) return 0;
 int top=r->scope?1:15;char *end=NULL;
 r->span=strtod(argv[3],&end);if(*end||r->span!=r->span||r->span<.001||r->span>3.0) {fprintf(stderr,"Choose a capture span from 1 ms to 3 seconds.\n");return 0;}
 for(int i=4;i<argc;i++) {
  char *key=argv[i],*value=strchr(key,'=');if(!value) return 0;*value++=0;
  if(!strcmp(key,"channels")) { for(char *p=value;*p;) { long ch=strtol(p,&end,10);if(end==p||ch<0||ch>top||r->count>=16) return 0;for(int j=0;j<r->count;j++) if(r->list[j]==ch) return 0;r->list[r->count++]=(int)ch;p=*end==','?end+1:end;if(*end&&*end!=',') return 0; } }
  else if(!strcmp(key,"trigger")) { if(!strcmp(value,"none")) r->trigger=-1; else { long ch=strtol(value,&end,10);if(*end||ch<0||ch>top) return 0;r->trigger=(int)ch; } }
  else if(!strcmp(key,"edge")) { if(strcmp(value,"rise")&&strcmp(value,"fall")) return 0;r->falling=!strcmp(value,"fall"); }
  else if(!strcmp(key,"mode")) { if(strcmp(value,"auto")&&strcmp(value,"normal")) return 0;r->normal=!strcmp(value,"normal"); }
  else if(!strcmp(key,"level")) { r->level=strtod(value,&end);if(*end||r->level!=r->level||fabs(r->level)>25) return 0; }
  else if(!strcmp(key,"position")) { r->position=strtod(value,&end);if(*end||r->position!=r->position||r->position<0||r->position>100) return 0; }
  else if(!strcmp(key,"range")) { r->range=strtod(value,&end);if(*end||(r->range!=5&&r->range!=50)) return 0; }
  else return 0;
 }
 if(!r->count) {r->list[0]=r->trigger>=0?r->trigger:0;r->count=1;}
 return 1;
}
// open the device configuration with the largest buffer for this instrument (ad2: 16k logic or scope samples)
static int open_device(int scope,int *handle) {
 int configs=0,best=-1,size=0;
 if(EnumConfig&&EnumConfigInfo&&DeviceConfigOpen&&EnumConfig(0,&configs)) for(int i=0;i<configs;i++) {int n=0;if(EnumConfigInfo(i,scope?7:9,&n)&&n>size) {size=n;best=i;}}
 return best>=0?DeviceConfigOpen(0,best,handle):DeviceOpen(-1,handle);
}
static int configure(int handle,const Request *r,int *count,double *rate) {
 if(r->scope) {
  int min=0,max=0;if(!AnalogInBufferSizeInfo(handle,&min,&max)||max<256) {error_message("Scope buffer unavailable");return 0;}
  *count=max<16384?max:16384;*rate=*count/r->span;
  int ok=AnalogInFrequencySet(handle,*rate)&&AnalogInBufferSizeSet(handle,*count);
  for(int ch=0;ch<2&&ok;ch++) { int on=ch==r->trigger;for(int j=0;j<r->count;j++) on|=r->list[j]==ch;ok=AnalogInChannelEnableSet(handle,ch,on)&&(!on||AnalogInChannelRangeSet(handle,ch,r->range)); }
  if(ok&&r->trigger<0) ok=AnalogInTriggerSourceSet(handle,0);
  else if(ok) { ok=AnalogInTriggerSourceSet(handle,2)&&AnalogInTriggerTypeSet(handle,0)&&AnalogInTriggerChannelSet(handle,r->trigger)&&AnalogInTriggerLevelSet(handle,r->level)&&AnalogInTriggerConditionSet(handle,r->falling)&&AnalogInTriggerAutoTimeoutSet(handle,r->normal?0:1.5);
   if(ok&&AnalogInTriggerPositionSet) ok=AnalogInTriggerPositionSet(handle,(.5-r->position/100)*r->span); }
  if(!ok||!AnalogInConfigure(handle,1,0)) {error_message("Scope setup failed");return 0;}
  AnalogInFrequencyGet(handle,rate);
 } else {
  int max=0;double clock=0;if(!DigitalInBufferSizeInfo(handle,&max)||max<256||!DigitalInInternalClockInfo(handle,&clock)) {error_message("Logic buffer unavailable");return 0;}
  *count=max<32768?max:32768;int divider=(int)ceil(clock*r->span/ *count);if(divider<1)divider=1;*rate=clock/divider;
  unsigned bit=r->trigger<0?0:1u<<r->trigger;
  int ok=DigitalInDividerSet(handle,(unsigned)divider)&&DigitalInSampleFormatSet(handle,16)&&DigitalInBufferSizeSet(handle,*count)&&DigitalInTriggerSourceSet(handle,r->trigger<0?0:3)&&DigitalInTriggerSet(handle,0,0,r->falling?0:bit,r->falling?bit:0)&&DigitalInTriggerAutoTimeoutSet(handle,r->normal?0:1.5);
  if(ok&&r->trigger>=0&&DigitalInTriggerPositionSet) ok=DigitalInTriggerPositionSet(handle,(unsigned)((1-r->position/100)* *count));
  if(!ok||!DigitalInConfigure(handle,1,0)) {error_message("Logic setup failed");return 0;}
 }
 return 1;
}
// 1 = frame printed, 0 = failed, -1 = stopped while waiting
static int acquire(int handle,const Request *r,int count,double rate,int run) {
 if(!(r->scope?AnalogInConfigure(handle,0,1):DigitalInConfigure(handle,0,1))) {error_message("Capture start failed");return 0;}
 int limit=(int)(r->span*100)+(r->normal?800:400);
 for(int attempt=0;;attempt++) {
  unsigned char state=0;int ok=r->scope?AnalogInStatus(handle,1,&state):DigitalInStatus(handle,1,&state);if(!ok) {error_message("Capture failed");return 0;}
  if(state==2) break;
  if(stopping||(run&&input_closed())) return -1;
  if(!run&&attempt>=limit) {fprintf(stderr,r->normal?"No trigger. Check the trigger source, edge and level, or use Auto.\n":"Capture timed out. Check the selected input and trigger.\n");return 0;}
  pause_ms(10);
 }
 double *volts=NULL;uint16_t *words=NULL;unsigned char *bits=(unsigned char*)calloc((size_t)count,1);int result=0;
 if(!bits) return 0;
 if(r->scope) {volts=(double*)calloc((size_t)count,sizeof(double));if(!volts) goto done;}
 else {words=(uint16_t*)calloc((size_t)count,sizeof(uint16_t));if(!words||!DigitalInStatusData(handle,words,count*2)) {error_message("Reading logic samples failed");goto done;}}
 double range=r->range;if(r->scope&&AnalogInChannelRangeGet) AnalogInChannelRangeGet(handle,r->list[0],&range);
 int stride=(count+1999)/2000;
 printf("{\"mode\":\"%s\",\"sampleRate\":%.9g,\"samples\":%d,\"span\":%.9g,\"range\":%.6g,\"dt\":%.9g,\"trigger\":%d,\"edge\":\"%s\",\"level\":%.6g,\"position\":%.6g,\"triggerMode\":\"%s\",\"triggerTime\":%.9g,\"traces\":[",r->scope?"scope":"logic",rate,count,count/rate,range,r->scope?stride/rate:1/rate,r->trigger,r->falling?"fall":"rise",r->level,r->position,r->normal?"normal":"auto",r->trigger<0?-1:r->position/100*count/rate);
 for(int j=0;j<r->count;j++) {
  int ch=r->list[j];double low=0,peak=0;
  if(r->scope) {if(!AnalogInStatusData(handle,ch,volts,count)) {error_message("Reading scope samples failed");goto done;}low=peak=volts[0];for(int i=0;i<count;i++) {bits[i]=volts[i]>=r->level;if(volts[i]<low)low=volts[i];if(volts[i]>peak)peak=volts[i];}}
  else for(int i=0;i<count;i++)bits[i]=(words[i]>>ch)&1;
  double period=0,high=0,duty=0;int cycles=analysis(bits,count,rate,&period,&high,&duty);
  printf("%s{\"channel\":%d,\"cycles\":%d,\"period\":%.9g,\"high\":%.9g,\"duty\":%.9g",j?",":"",ch,cycles,period,high,duty);
  if(r->scope) {printf(",\"min\":%.5g,\"max\":%.5g,\"values\":[",low,peak);for(int i=0;i<count;i+=stride)printf("%s%.5g",i?",":"",volts[i]);}
  else {printf(",\"values\":[");for(int i=0;i<count;i++)if(i==0||bits[i]!=bits[i-1])printf("%s[%d,%d]",i?",":"",i,bits[i]);}
  printf("]}");
 }
 puts("]}");fflush(stdout);result=1;
 done:free(bits);free(volts);free(words);return result;
}
int main(int argc,char **argv) {
 if(argc==2&&strcmp(argv[1],"self-test")==0) {
  unsigned char samples[500]={0};for(int i=0;i<500;i++)samples[i]=(i%200)<20;double p,h,d;int n=analysis(samples,500,10000,&p,&h,&d);if(n!=1||fabs(p-.02)>1e-9||fabs(h-.002)>1e-9||fabs(d-10)>1e-9)return 1;
  char a0[]="aster-ad2",a1[]="capture",a2[]="logic",a3[]="0.05",a4[]="channels=2,0,5",a5[]="trigger=5",a6[]="edge=fall",a7[]="mode=normal",a8[]="position=25";char *ok[]={a0,a1,a2,a3,a4,a5,a6,a7,a8};Request r;
  if(!parse(9,ok,&r)||r.scope||r.count!=3||r.list[0]!=2||r.list[2]!=5||r.trigger!=5||!r.falling||!r.normal||r.position!=25||r.level!=1.5)return 1;
  char b2[]="scope",b4[]="channels=0,2",b5[]="channels=1,1",b6[]="trigger=none",b7[]="range=10",b8[]="level=1.2",b9[]="bogus=1";
  char *bad1[]={a0,a1,b2,a3,b4},*bad2[]={a0,a1,a2,a3,b5},*bad3[]={a0,a1,b2,a3,b7},*bad4[]={a0,a1,a2,a3,b9},*good[]={a0,a1,b2,a3,b6,b8};
  if(parse(5,bad1,&r)||parse(5,bad2,&r)||parse(5,bad3,&r)||parse(5,bad4,&r)||!parse(6,good,&r)||!r.scope||r.trigger!=-1||r.count!=1||r.list[0]!=0||r.level!=1.2||r.range!=50)return 1;
  puts("AD2 capture analysis and request parsing passed");return 0;
 }
 int run=argc>1&&strcmp(argv[1],"run")==0;
 if(argc<2||(strcmp(argv[1],"status")&&strcmp(argv[1],"capture")&&!run)) {fprintf(stderr,"Usage: aster-ad2 status | capture|run scope|logic span-seconds [channels=0,1] [trigger=N|none] [edge=rise|fall] [level=V] [position=%%] [mode=auto|normal] [range=5|50]\n");return 2;}
 Request r;if(strcmp(argv[1],"status")&&!parse(argc,argv,&r)) {fprintf(stderr,"Invalid capture request.\n");return 2;}
 int loaded=load_library();if(loaded)return loaded;
 int devices=0;if(!Enum(0,&devices)) {error_message("Device enumeration failed");return 2;}
 if(strcmp(argv[1],"status")==0) {char name[32]={0};if(devices>0)EnumDeviceName(0,name);printf("{\"installed\":true,\"devices\":%d,\"name\":",devices);json_string(name);puts("}");return 0;}
 if(devices<1) {fprintf(stderr,"No Analog Discovery device found. Connect it and close any WaveForms session using it.\n");return 2;}
 signal(SIGINT,on_signal);signal(SIGTERM,on_signal);
 int handle=0;if(!open_device(r.scope,&handle)||!handle) {error_message("Could not open Analog Discovery");return 2;}
 int count=0,result=2;double rate=0;
 if(configure(handle,&r,&count,&rate)) {
  if(!run) result=acquire(handle,&r,count,rate,0)==1?0:2;
  else for(;;) {int got=acquire(handle,&r,count,rate,1);if(got<=0) {result=got<0?0:2;break;}if(stopping||input_closed()) {result=0;break;}pause_ms(30);}
 }
 DeviceClose(handle);return result;
}
