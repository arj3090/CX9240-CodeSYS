// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Manufacturing Automation, LLC
// upsbus: stream UPS status together with the EtherCAT output byte the PLC is sending.
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sched.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <arpa/inet.h>
static int64_t now_us(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1000000LL+t.tv_nsec/1000; }
int main(void){
  int fd=open("/sys/class/power_supply/ups/status",O_RDONLY); if(fd<0){perror("status");return 1;}
  int s=socket(AF_PACKET,SOCK_RAW,htons(0x88A4)); if(s<0){perror("socket");return 1;}
  struct sockaddr_ll a={0}; a.sll_family=AF_PACKET; a.sll_protocol=htons(0x88A4); a.sll_ifindex=if_nametoindex("eth0");
  if(bind(s,(struct sockaddr*)&a,sizeof a)){perror("bind");return 1;}
  struct timeval tv={0,3000}; setsockopt(s,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof tv);
  mlockall(MCL_CURRENT|MCL_FUTURE); struct sched_param sp={.sched_priority=40}; sched_setscheduler(0,SCHED_FIFO,&sp);
  fcntl(1,F_SETFL,fcntl(1,F_GETFL)|O_NONBLOCK);
  unsigned char d[2000]; char st[32]="",pst[32]="",line[160]; int out=-1,pout=-2,wkc=-1,pwkc=-2; long k=0; int64_t t0=now_us(),lastf=0; int stalled=0;
  for(;;k++){
    struct sockaddr_ll f; socklen_t fl=sizeof f; int n=recvfrom(s,d,sizeof d,0,(struct sockaddr*)&f,&fl);
    int64_t t=now_us(); int gotf=0;
    if(n>=26 && f.sll_pkttype!=PACKET_OUTGOING){ int o=16;
      for(;;){ if(o+10>n)break; uint16_t lf=d[o+6]|d[o+7]<<8; int len=lf&0x7ff; if(o+12+len>n)break;
        if(d[o]==11&&len>=1){ out=d[o+10]; wkc=d[o+10+len]|d[o+11+len]<<8; gotf=1; }
        o+=12+len; if(!(lf&0x8000))break; } }
    if(gotf){ lastf=t; if(stalled){ stalled=0; int m=snprintf(line,sizeof line,"EVENT t_ms=%.1f bus frames resumed\n",(t-t0)/1000.0); write(1,line,m);} }
    else if(lastf && !stalled && t-lastf>5000){ stalled=1; int m=snprintf(line,sizeof line,"EVENT t_ms=%.1f no process-data frame for 5 ms (last at t_ms=%.1f)\n",(t-t0)/1000.0,(lastf-t0)/1000.0); write(1,line,m); }
    int r=pread(fd,st,31,0); if(r<0)r=0; st[r]=0; char*p=strchr(st,10); if(p)*p=0;
    if(strcmp(st,pst)){ int m=snprintf(line,sizeof line,"EVENT t_ms=%.1f ups_status \"%s\" -> \"%s\"\n",(t-t0)/1000.0,pst,st); write(1,line,m); strcpy(pst,st); }
    if(out!=pout){ int m=snprintf(line,sizeof line,"EVENT t_ms=%.1f output_byte 0x%02x -> 0x%02x\n",(t-t0)/1000.0,pout&0xff,out&0xff); write(1,line,m); pout=out; }
    if(wkc!=pwkc){ int m=snprintf(line,sizeof line,"EVENT t_ms=%.1f lwr_wkc %d -> %d\n",(t-t0)/1000.0,pwkc,wkc); write(1,line,m); pwkc=wkc; }
    if(k%20==0){ int m=snprintf(line,sizeof line,"t_ms=%.1f ups=%s out=0x%02x wkc=%d%s\n",(t-t0)/1000.0,st,out&0xff,wkc,stalled?" BUS-STALLED":""); write(1,line,m); }
  }
}
