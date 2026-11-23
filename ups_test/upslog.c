// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Manufacturing Automation, LLC
// upslog: measure CX9240 internal UPS behaviour on power loss.
// Stream: one line per 2 ms on stdout (meant to be read over ssh by another machine).
// Disk:   after the status changes, write+fdatasync numbered records to a file as fast as possible.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sched.h>
#include <pthread.h>
#include <sys/mman.h>
static const char *ST="/sys/class/power_supply/ups/status";
static volatile int changed=0; static volatile int64_t t_change=0; static char st0[32]="", stN[32]="";
static int64_t now_us(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1000000LL+t.tv_nsec/1000; }
static void rdst(int fd,char*b){ int n=pread(fd,b,31,0); if(n<0)n=0; b[n]=0; char*p=strchr(b,10); if(p)*p=0; }
static void *disk(void *arg){
  const char *path=arg; int fd=open(path,O_WRONLY|O_CREAT|O_TRUNC,0644); if(fd<0){perror(path);return 0;}
  char rec[128]; int n=snprintf(rec,sizeof rec,"armed initial_status=%s\n",st0); write(fd,rec,n); fsync(fd);
  while(!changed) usleep(200);
  for(int seq=0;;seq++){
    int64_t a=now_us();
    n=snprintf(rec,sizeof rec,"seq=%d written_at_ms_after_change=%.1f status=%s\n",seq,(a-t_change)/1000.0,stN);
    write(fd,rec,n); fdatasync(fd);
    int64_t b=now_us();
    n=snprintf(rec,sizeof rec,"  sync_done seq=%d took_ms=%.1f at_ms_after_change=%.1f\n",seq,(b-a)/1000.0,(b-t_change)/1000.0);
    write(fd,rec,n);
    if(seq>20000) break;
  }
  return 0; }
int main(int c,char**v){
  const char *path=c>1?v[1]:"/home/Administrator/upstest/disk.log"; int simulate=c>2?atoi(v[2]):0;
  int fd=open(ST,O_RDONLY); if(fd<0){perror(ST);return 1;}
  rdst(fd,st0); strcpy(stN,st0);
  mlockall(MCL_CURRENT|MCL_FUTURE);
  pthread_t th; pthread_create(&th,0,disk,(void*)path);
  struct sched_param sp={.sched_priority=40}; if(sched_setscheduler(0,SCHED_FIFO,&sp)) perror("sched_setscheduler (continuing)");
  fcntl(1,F_SETFL,fcntl(1,F_GETFL)|O_NONBLOCK);
  int64_t t0=now_us(); struct timespec nx; clock_gettime(CLOCK_MONOTONIC,&nx); char cur[32],line[96]; long i=0;
  int n=snprintf(line,sizeof line,"START status=%s\n",st0); write(1,line,n);
  for(;;i++){
    nx.tv_nsec+=1000000; if(nx.tv_nsec>=1000000000){nx.tv_nsec-=1000000000;nx.tv_sec++;}
    clock_nanosleep(CLOCK_MONOTONIC,TIMER_ABSTIME,&nx,0);
    int64_t t=now_us(); rdst(fd,cur);
    if(simulate && !changed && t-t0>simulate*1000000LL) strcpy(cur,"SIMULATED");
    if(strcmp(cur,stN)){ strcpy(stN,cur); if(!changed){ t_change=t; changed=1; }
      n=snprintf(line,sizeof line,"CHANGE t_ms=%.1f status=%s\n",(t-t0)/1000.0,cur); write(1,line,n); }
    if(i%2==0){ n=snprintf(line,sizeof line,"t_ms=%.1f %s%s\n",(t-t0)/1000.0,cur,changed?" (after change)":""); write(1,line,n); }
    if(simulate && changed && t-t_change>3000000) return 0;
  }
}
