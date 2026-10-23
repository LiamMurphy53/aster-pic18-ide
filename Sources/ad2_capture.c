// Optional WaveForms SDK bridge. Loads the user's installed DWF runtime at run time.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#ifdef _WIN32
#include <windows.h>
static HMODULE library;
static void *symbol(const char *name) { return (void *)GetProcAddress(library, name); }
static void pause_ms(int ms) { Sleep((DWORD)ms); }
#else
#include <dlfcn.h>
#include <unistd.h>
static void *library;
static void *symbol(const char *name) { return dlsym(library, name); }
static void pause_ms(int ms) { usleep((useconds_t)ms * 1000); }
#endif
#define LOAD(fn) do { *(void **)(&fn) = symbol("FDwf" #fn); if (!fn) { fprintf(stderr,"WaveForms SDK is missing FDwf%s\n",#fn); return 2; } } while (0)
static int (*GetLastErrorMsg)(char *);
static int (*Enum)(int,int *);
static int (*EnumDeviceName)(int,char *);
static int (*DeviceOpen)(int,int *);
static int (*DeviceClose)(int);
static int (*AnalogInFrequencySet)(int,double);
static int (*AnalogInFrequencyGet)(int,double *);
static int (*AnalogInBufferSizeInfo)(int,int *,int *);
static int (*AnalogInBufferSizeSet)(int,int);
static int (*AnalogInChannelEnableSet)(int,int,int);
static int (*AnalogInChannelRangeSet)(int,int,double);
static int (*AnalogInTriggerSourceSet)(int,unsigned char);
static int (*AnalogInTriggerTypeSet)(int,unsigned char);
static int (*AnalogInTriggerChannelSet)(int,int);
static int (*AnalogInTriggerLevelSet)(int,double);
static int (*AnalogInTriggerAutoTimeoutSet)(int,double);
static int (*AnalogInConfigure)(int,int,int);
static int (*AnalogInStatus)(int,int,unsigned char *);
static int (*AnalogInStatusData)(int,int,double *,int);
static int (*DigitalInInternalClockInfo)(int,double *);
static int (*DigitalInDividerSet)(int,int);
static int (*DigitalInSampleFormatSet)(int,int);
static int (*DigitalInBufferSizeInfo)(int,int *);
static int (*DigitalInBufferSizeSet)(int,int);
static int (*DigitalInTriggerSourceSet)(int,unsigned char);
static int (*DigitalInTriggerSet)(int,unsigned int,unsigned int,unsigned int,unsigned int);
static int (*DigitalInTriggerAutoTimeoutSet)(int,double);
static int (*DigitalInConfigure)(int,int,int);
static int (*DigitalInStatus)(int,int,unsigned char *);
static int (*DigitalInStatusData)(int,void *,int);
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
 LOAD(AnalogInFrequencySet);LOAD(AnalogInFrequencyGet);LOAD(AnalogInBufferSizeInfo);LOAD(AnalogInBufferSizeSet);LOAD(AnalogInChannelEnableSet);LOAD(AnalogInChannelRangeSet);LOAD(AnalogInTriggerSourceSet);LOAD(AnalogInTriggerTypeSet);LOAD(AnalogInTriggerChannelSet);LOAD(AnalogInTriggerLevelSet);LOAD(AnalogInTriggerAutoTimeoutSet);LOAD(AnalogInConfigure);LOAD(AnalogInStatus);LOAD(AnalogInStatusData);
 LOAD(DigitalInInternalClockInfo);LOAD(DigitalInDividerSet);LOAD(DigitalInSampleFormatSet);LOAD(DigitalInBufferSizeInfo);LOAD(DigitalInBufferSizeSet);LOAD(DigitalInTriggerSourceSet);LOAD(DigitalInTriggerSet);LOAD(DigitalInTriggerAutoTimeoutSet);LOAD(DigitalInConfigure);LOAD(DigitalInStatus);LOAD(DigitalInStatusData);
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
int main(int argc,char **argv) {
 if(argc==2&&strcmp(argv[1],"self-test")==0) {unsigned char samples[500]={0};for(int i=0;i<500;i++)samples[i]=(i%200)<20;double p,h,d;int n=analysis(samples,500,10000,&p,&h,&d);if(n!=1||fabs(p-.02)>1e-9||fabs(h-.002)>1e-9||fabs(d-10)>1e-9)return 1;puts("AD2 capture analysis passed");return 0;}
 if(argc<2||argc>5) {fprintf(stderr,"Usage: aster-ad2 status | capture scope|logic span-seconds channel\n");return 2;}
 int loaded=load_library();if(loaded)return loaded;
 int devices=0;if(!Enum(0,&devices)) {error_message("Device enumeration failed");return 2;}
 if(strcmp(argv[1],"status")==0) {char name[32]={0};if(devices>0)EnumDeviceName(0,name);printf("{\"installed\":true,\"devices\":%d,\"name\":",devices);json_string(name);puts("}");return 0;}
 if(argc!=5||strcmp(argv[1],"capture")) {fprintf(stderr,"Invalid capture request.\n");return 2;}
 int scope=strcmp(argv[2],"scope")==0,logic=strcmp(argv[2],"logic")==0;if(!scope&&!logic)return 2;
 char *end=NULL;double span=strtod(argv[3],&end);if(*end||span!=span||span<.001||span>3.0) {fprintf(stderr,"Choose a capture span from 1 ms to 3 seconds.\n");return 2;}
 long channel=strtol(argv[4],&end,10);if(*end||channel<0||channel>(scope?1:15)) {fprintf(stderr,"Invalid capture channel.\n");return 2;}
 if(devices<1) {fprintf(stderr,"No Analog Discovery device found. Connect it and close any WaveForms session using it.\n");return 2;}
 int handle=0;if(!DeviceOpen(-1,&handle)||!handle) {error_message("Could not open Analog Discovery");return 2;}
 int count=0;double rate=0;double *volts=NULL;uint16_t *words=NULL;unsigned char *bits=NULL;int result=2;
 if(scope) {
  int min=0,max=0;if(!AnalogInBufferSizeInfo(handle,&min,&max)||max<256) {error_message("Scope buffer unavailable");goto done;}
  count=max<8192?max:8192;rate=count/span;
  if(!AnalogInFrequencySet(handle,rate)||!AnalogInBufferSizeSet(handle,count)||!AnalogInChannelEnableSet(handle,(int)channel,1)||!AnalogInChannelRangeSet(handle,(int)channel,5.0)||!AnalogInTriggerSourceSet(handle,2)||!AnalogInTriggerTypeSet(handle,0)||!AnalogInTriggerChannelSet(handle,(int)channel)||!AnalogInTriggerLevelSet(handle,2.5)||!AnalogInTriggerAutoTimeoutSet(handle,.5)||!AnalogInConfigure(handle,1,0)) {error_message("Scope setup failed");goto done;}
  AnalogInFrequencyGet(handle,&rate);if(!AnalogInConfigure(handle,0,1)) {error_message("Scope start failed");goto done;}
 } else {
  int max=0;double clock=0;if(!DigitalInBufferSizeInfo(handle,&max)||max<256||!DigitalInInternalClockInfo(handle,&clock)) {error_message("Logic buffer unavailable");goto done;}
  count=max<16384?max:16384;int divider=(int)ceil(clock*span/count);if(divider<1)divider=1;rate=clock/divider;
  if(!DigitalInDividerSet(handle,divider)||!DigitalInSampleFormatSet(handle,16)||!DigitalInBufferSizeSet(handle,count)||!DigitalInTriggerSourceSet(handle,3)||!DigitalInTriggerSet(handle,0,0,1u<<channel,0)||!DigitalInTriggerAutoTimeoutSet(handle,.5)||!DigitalInConfigure(handle,1,1)) {error_message("Logic setup failed");goto done;}
 }
 for(int attempt=0;attempt<500;attempt++) {unsigned char state=0;int ok=scope?AnalogInStatus(handle,1,&state):DigitalInStatus(handle,1,&state);if(!ok) {error_message("Capture failed");goto done;}if(state==2)break;if(attempt==499) {fprintf(stderr,"Capture timed out. Check the selected input and trigger.\n");goto done;}pause_ms(10);}
 bits=(unsigned char*)calloc((size_t)count,1);if(!bits)goto done;
 if(scope) {volts=(double*)calloc((size_t)count,sizeof(double));if(!volts||!AnalogInStatusData(handle,(int)channel,volts,count)) {error_message("Reading scope samples failed");goto done;}for(int i=0;i<count;i++)bits[i]=volts[i]>=2.5;}
 else {words=(uint16_t*)calloc((size_t)count,sizeof(uint16_t));if(!words||!DigitalInStatusData(handle,words,count*2)) {error_message("Reading logic samples failed");goto done;}for(int i=0;i<count;i++)bits[i]=(words[i]>>channel)&1;}
 double period=0,high=0,duty=0;int cycles=analysis(bits,count,rate,&period,&high,&duty);
 printf("{\"mode\":\"%s\",\"channel\":%ld,\"sampleRate\":%.9g,\"samples\":%d,\"span\":%.9g,\"cycles\":%d,\"period\":%.9g,\"high\":%.9g,\"duty\":%.9g,\"values\":[",scope?"scope":"logic",channel,rate,count,count/rate,cycles,period,high,duty);
 if(scope) {int stride=(count+1199)/1200;for(int i=0;i<count;i+=stride)printf("%s%.5g",i?",":"",volts[i]);}
 else {for(int i=0;i<count;i++)if(i==0||bits[i]!=bits[i-1])printf("%s[%d,%d]",i?",":"",i,bits[i]);}
 puts("]}");result=0;
 done:free(bits);free(volts);free(words);DeviceClose(handle);return result;
}
