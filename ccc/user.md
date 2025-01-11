## ../user/cat.c 
```c
#include "kernel/types.h"
#include "kernel/fcntl.h"
#include "user/user.h"

char buf[512];

void
cat(int fd)
{
  int n;

  while((n = read(fd, buf, sizeof(buf))) > 0) {
    if (write(1, buf, n) != n) {
      fprintf(2, "cat: write error\n");
      exit(1);
    }
  }
  if(n < 0){
    fprintf(2, "cat: read error\n");
    exit(1);
  }
}

int
main(int argc, char *argv[])
{
  int fd, i;

  if(argc <= 1){
    cat(0);
    exit(0);
  }

  for(i = 1; i < argc; i++){
    if((fd = open(argv[i], O_RDONLY)) < 0){
      fprintf(2, "cat: cannot open %s\n", argv[i]);
      exit(1);
    }
    cat(fd);
    close(fd);
  }
  exit(0);
}
```
## ../user/echo.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int
main(int argc, char *argv[])
{
  int i;

  for(i = 1; i < argc; i++){
    write(1, argv[i], strlen(argv[i]));
    if(i + 1 < argc){
      write(1, " ", 1);
    } else {
      write(1, "\n", 1);
    }
  }
  exit(0);
}
```
## ../user/forktest.c 
```c
// Test that fork fails gracefully.
// Tiny executable so that the limit can be filling the proc table.

#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

#define N  1000

void
print(const char *s)
{
  write(1, s, strlen(s));
}

void
forktest(void)
{
  int n, pid;

  print("fork test\n");

  for(n=0; n<N; n++){
    pid = fork();
    if(pid < 0)
      break;
    if(pid == 0)
      exit(0);
  }

  if(n == N){
    print("fork claimed to work N times!\n");
    exit(1);
  }

  for(; n > 0; n--){
    if(wait(0) < 0){
      print("wait stopped early\n");
      exit(1);
    }
  }

  if(wait(0) != -1){
    print("wait got too many\n");
    exit(1);
  }

  print("fork test OK\n");
}

int
main(void)
{
  forktest();
  exit(0);
}
```
## ../user/grep.c 
```c
// Simple grep.  Only supports ^ . * $ operators.

#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"

char buf[1024];
int match(char*, char*);

void
grep(char *pattern, int fd)
{
  int n, m;
  char *p, *q;

  m = 0;
  while((n = read(fd, buf+m, sizeof(buf)-m-1)) > 0){
    m += n;
    buf[m] = '\0';
    p = buf;
    while((q = strchr(p, '\n')) != 0){
      *q = 0;
      if(match(pattern, p)){
        *q = '\n';
        write(1, p, q+1 - p);
      }
      p = q+1;
    }
    if(m > 0){
      m -= p - buf;
      memmove(buf, p, m);
    }
  }
}

int
main(int argc, char *argv[])
{
  int fd, i;
  char *pattern;

  if(argc <= 1){
    fprintf(2, "usage: grep pattern [file ...]\n");
    exit(1);
  }
  pattern = argv[1];

  if(argc <= 2){
    grep(pattern, 0);
    exit(0);
  }

  for(i = 2; i < argc; i++){
    if((fd = open(argv[i], O_RDONLY)) < 0){
      printf("grep: cannot open %s\n", argv[i]);
      exit(1);
    }
    grep(pattern, fd);
    close(fd);
  }
  exit(0);
}

// Regexp matcher from Kernighan & Pike,
// The Practice of Programming, Chapter 9, or
// https://www.cs.princeton.edu/courses/archive/spr09/cos333/beautiful.html

int matchhere(char*, char*);
int matchstar(int, char*, char*);

int
match(char *re, char *text)
{
  if(re[0] == '^')
    return matchhere(re+1, text);
  do{  // must look at empty string
    if(matchhere(re, text))
      return 1;
  }while(*text++ != '\0');
  return 0;
}

// matchhere: search for re at beginning of text
int matchhere(char *re, char *text)
{
  if(re[0] == '\0')
    return 1;
  if(re[1] == '*')
    return matchstar(re[0], re+2, text);
  if(re[0] == '$' && re[1] == '\0')
    return *text == '\0';
  if(*text!='\0' && (re[0]=='.' || re[0]==*text))
    return matchhere(re+1, text+1);
  return 0;
}

// matchstar: search for c*re at beginning of text
int matchstar(int c, char *re, char *text)
{
  do{  // a * matches zero or more instances
    if(matchhere(re, text))
      return 1;
  }while(*text!='\0' && (*text++==c || c=='.'));
  return 0;
}

```
## ../user/grind.c 
```c
//
// run random system calls in parallel forever.
//

#include "kernel/param.h"
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"
#include "kernel/fcntl.h"
#include "kernel/syscall.h"
#include "kernel/memlayout.h"
#include "kernel/riscv.h"

// from FreeBSD.
int
do_rand(unsigned long *ctx)
{
/*
 * Compute x = (7^5 * x) mod (2^31 - 1)
 * without overflowing 31 bits:
 *      (2^31 - 1) = 127773 * (7^5) + 2836
 * From "Random number generators: good ones are hard to find",
 * Park and Miller, Communications of the ACM, vol. 31, no. 10,
 * October 1988, p. 1195.
 */
    long hi, lo, x;

    /* Transform to [1, 0x7ffffffe] range. */
    x = (*ctx % 0x7ffffffe) + 1;
    hi = x / 127773;
    lo = x % 127773;
    x = 16807 * lo - 2836 * hi;
    if (x < 0)
        x += 0x7fffffff;
    /* Transform to [0, 0x7ffffffd] range. */
    x--;
    *ctx = x;
    return (x);
}

unsigned long rand_next = 1;

int
rand(void)
{
    return (do_rand(&rand_next));
}

void
go(int which_child)
{
  int fd = -1;
  static char buf[999];
  char *break0 = sbrk(0);
  uint64 iters = 0;

  mkdir("grindir");
  if(chdir("grindir") != 0){
    printf("grind: chdir grindir failed\n");
    exit(1);
  }
  chdir("/");
  
  while(1){
    iters++;
    if((iters % 500) == 0)
      write(1, which_child?"B":"A", 1);
    int what = rand() % 23;
    if(what == 1){
      close(open("grindir/../a", O_CREATE|O_RDWR));
    } else if(what == 2){
      close(open("grindir/../grindir/../b", O_CREATE|O_RDWR));
    } else if(what == 3){
      unlink("grindir/../a");
    } else if(what == 4){
      if(chdir("grindir") != 0){
        printf("grind: chdir grindir failed\n");
        exit(1);
      }
      unlink("../b");
      chdir("/");
    } else if(what == 5){
      close(fd);
      fd = open("/grindir/../a", O_CREATE|O_RDWR);
    } else if(what == 6){
      close(fd);
      fd = open("/./grindir/./../b", O_CREATE|O_RDWR);
    } else if(what == 7){
      write(fd, buf, sizeof(buf));
    } else if(what == 8){
      read(fd, buf, sizeof(buf));
    } else if(what == 9){
      mkdir("grindir/../a");
      close(open("a/../a/./a", O_CREATE|O_RDWR));
      unlink("a/a");
    } else if(what == 10){
      mkdir("/../b");
      close(open("grindir/../b/b", O_CREATE|O_RDWR));
      unlink("b/b");
    } else if(what == 11){
      unlink("b");
      link("../grindir/./../a", "../b");
    } else if(what == 12){
      unlink("../grindir/../a");
      link(".././b", "/grindir/../a");
    } else if(what == 13){
      int pid = fork();
      if(pid == 0){
        exit(0);
      } else if(pid < 0){
        printf("grind: fork failed\n");
        exit(1);
      }
      wait(0);
    } else if(what == 14){
      int pid = fork();
      if(pid == 0){
        fork();
        fork();
        exit(0);
      } else if(pid < 0){
        printf("grind: fork failed\n");
        exit(1);
      }
      wait(0);
    } else if(what == 15){
      sbrk(6011);
    } else if(what == 16){
      if(sbrk(0) > break0)
        sbrk(-(sbrk(0) - break0));
    } else if(what == 17){
      int pid = fork();
      if(pid == 0){
        close(open("a", O_CREATE|O_RDWR));
        exit(0);
      } else if(pid < 0){
        printf("grind: fork failed\n");
        exit(1);
      }
      if(chdir("../grindir/..") != 0){
        printf("grind: chdir failed\n");
        exit(1);
      }
      kill(pid);
      wait(0);
    } else if(what == 18){
      int pid = fork();
      if(pid == 0){
        kill(getpid());
        exit(0);
      } else if(pid < 0){
        printf("grind: fork failed\n");
        exit(1);
      }
      wait(0);
    } else if(what == 19){
      int fds[2];
      if(pipe(fds) < 0){
        printf("grind: pipe failed\n");
        exit(1);
      }
      int pid = fork();
      if(pid == 0){
        fork();
        fork();
        if(write(fds[1], "x", 1) != 1)
          printf("grind: pipe write failed\n");
        char c;
        if(read(fds[0], &c, 1) != 1)
          printf("grind: pipe read failed\n");
        exit(0);
      } else if(pid < 0){
        printf("grind: fork failed\n");
        exit(1);
      }
      close(fds[0]);
      close(fds[1]);
      wait(0);
    } else if(what == 20){
      int pid = fork();
      if(pid == 0){
        unlink("a");
        mkdir("a");
        chdir("a");
        unlink("../a");
        fd = open("x", O_CREATE|O_RDWR);
        unlink("x");
        exit(0);
      } else if(pid < 0){
        printf("grind: fork failed\n");
        exit(1);
      }
      wait(0);
    } else if(what == 21){
      unlink("c");
      // should always succeed. check that there are free i-nodes,
      // file descriptors, blocks.
      int fd1 = open("c", O_CREATE|O_RDWR);
      if(fd1 < 0){
        printf("grind: create c failed\n");
        exit(1);
      }
      if(write(fd1, "x", 1) != 1){
        printf("grind: write c failed\n");
        exit(1);
      }
      struct stat st;
      if(fstat(fd1, &st) != 0){
        printf("grind: fstat failed\n");
        exit(1);
      }
      if(st.size != 1){
        printf("grind: fstat reports wrong size %d\n", (int)st.size);
        exit(1);
      }
      if(st.ino > 200){
        printf("grind: fstat reports crazy i-number %d\n", st.ino);
        exit(1);
      }
      close(fd1);
      unlink("c");
    } else if(what == 22){
      // echo hi | cat
      int aa[2], bb[2];
      if(pipe(aa) < 0){
        fprintf(2, "grind: pipe failed\n");
        exit(1);
      }
      if(pipe(bb) < 0){
        fprintf(2, "grind: pipe failed\n");
        exit(1);
      }
      int pid1 = fork();
      if(pid1 == 0){
        close(bb[0]);
        close(bb[1]);
        close(aa[0]);
        close(1);
        if(dup(aa[1]) != 1){
          fprintf(2, "grind: dup failed\n");
          exit(1);
        }
        close(aa[1]);
        char *args[3] = { "echo", "hi", 0 };
        exec("grindir/../echo", args);
        fprintf(2, "grind: echo: not found\n");
        exit(2);
      } else if(pid1 < 0){
        fprintf(2, "grind: fork failed\n");
        exit(3);
      }
      int pid2 = fork();
      if(pid2 == 0){
        close(aa[1]);
        close(bb[0]);
        close(0);
        if(dup(aa[0]) != 0){
          fprintf(2, "grind: dup failed\n");
          exit(4);
        }
        close(aa[0]);
        close(1);
        if(dup(bb[1]) != 1){
          fprintf(2, "grind: dup failed\n");
          exit(5);
        }
        close(bb[1]);
        char *args[2] = { "cat", 0 };
        exec("/cat", args);
        fprintf(2, "grind: cat: not found\n");
        exit(6);
      } else if(pid2 < 0){
        fprintf(2, "grind: fork failed\n");
        exit(7);
      }
      close(aa[0]);
      close(aa[1]);
      close(bb[1]);
      char buf[4] = { 0, 0, 0, 0 };
      read(bb[0], buf+0, 1);
      read(bb[0], buf+1, 1);
      read(bb[0], buf+2, 1);
      close(bb[0]);
      int st1, st2;
      wait(&st1);
      wait(&st2);
      if(st1 != 0 || st2 != 0 || strcmp(buf, "hi\n") != 0){
        printf("grind: exec pipeline failed %d %d \"%s\"\n", st1, st2, buf);
        exit(1);
      }
    }
  }
}

void
iter()
{
  unlink("a");
  unlink("b");
  
  int pid1 = fork();
  if(pid1 < 0){
    printf("grind: fork failed\n");
    exit(1);
  }
  if(pid1 == 0){
    rand_next ^= 31;
    go(0);
    exit(0);
  }

  int pid2 = fork();
  if(pid2 < 0){
    printf("grind: fork failed\n");
    exit(1);
  }
  if(pid2 == 0){
    rand_next ^= 7177;
    go(1);
    exit(0);
  }

  int st1 = -1;
  wait(&st1);
  if(st1 != 0){
    kill(pid1);
    kill(pid2);
  }
  int st2 = -1;
  wait(&st2);

  exit(0);
}

int
main()
{
  while(1){
    int pid = fork();
    if(pid == 0){
      iter();
      exit(0);
    }
    if(pid > 0){
      wait(0);
    }
    sleep(20);
    rand_next += 1;
  }
}
```
## ../user/init.c 
```c
// init: The initial user-level program

#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/spinlock.h"
#include "kernel/sleeplock.h"
#include "kernel/fs.h"
#include "kernel/file.h"
#include "user/user.h"
#include "kernel/fcntl.h"

char *argv[] = { "sh", 0 };

int
main(void)
{
  int pid, wpid;

  if(open("console", O_RDWR) < 0){
    mknod("console", CONSOLE, 0);
    open("console", O_RDWR);
  }
  dup(0);  // stdout
  dup(0);  // stderr

  for(;;){
    printf("init: starting sh\n");
    pid = fork();
    if(pid < 0){
      printf("init: fork failed\n");
      exit(1);
    }
    if(pid == 0){
      exec("sh", argv);
      printf("init: exec sh failed\n");
      exit(1);
    }

    for(;;){
      // this call to wait() returns if the shell exits,
      // or if a parentless process exits.
      wpid = wait((int *) 0);
      if(wpid == pid){
        // the shell exited; restart it.
        break;
      } else if(wpid < 0){
        printf("init: wait returned an error\n");
        exit(1);
      } else {
        // it was a parentless process; do nothing.
      }
    }
  }
}
```
## ../user/initcode.S 
```c
# Initial process that execs /init.
# This code runs in user space.

#include "syscall.h"

# exec(init, argv)
.globl start
start:
        la a0, init
        la a1, argv
        li a7, SYS_exec
        ecall

# for(;;) exit();
exit:
        li a7, SYS_exit
        ecall
        jal exit

# char init[] = "/init\0";
init:
  .string "/init\0"

# char *argv[] = { init, 0 };
.p2align 2
argv:
  .quad init
  .quad 0
```
## ../user/kill.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int
main(int argc, char **argv)
{
  int i;

  if(argc < 2){
    fprintf(2, "usage: kill pid...\n");
    exit(1);
  }
  for(i=1; i<argc; i++)
    kill(atoi(argv[i]));
  exit(0);
}
```
## ../user/ln.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int
main(int argc, char *argv[])
{
  if(argc != 3){
    fprintf(2, "Usage: ln old new\n");
    exit(1);
  }
  if(link(argv[1], argv[2]) < 0)
    fprintf(2, "link %s %s: failed\n", argv[1], argv[2]);
  exit(0);
}
```
## ../user/ls.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"
#include "kernel/fcntl.h"

char*
fmtname(char *path)
{
  static char buf[DIRSIZ+1];
  char *p;

  // Find first character after last slash.
  for(p=path+strlen(path); p >= path && *p != '/'; p--)
    ;
  p++;

  // Return blank-padded name.
  if(strlen(p) >= DIRSIZ)
    return p;
  memmove(buf, p, strlen(p));
  memset(buf+strlen(p), ' ', DIRSIZ-strlen(p));
  return buf;
}

void
ls(char *path)
{
  char buf[512], *p;
  int fd;
  struct dirent de;
  struct stat st;

  if((fd = open(path, O_RDONLY)) < 0){
    fprintf(2, "ls: cannot open %s\n", path);
    return;
  }

  if(fstat(fd, &st) < 0){
    fprintf(2, "ls: cannot stat %s\n", path);
    close(fd);
    return;
  }

  switch(st.type){
  case T_DEVICE:
  case T_FILE:
    printf("%s %d %d %d\n", fmtname(path), st.type, st.ino, (int) st.size);
    break;

  case T_DIR:
    if(strlen(path) + 1 + DIRSIZ + 1 > sizeof buf){
      printf("ls: path too long\n");
      break;
    }
    strcpy(buf, path);
    p = buf+strlen(buf);
    *p++ = '/';
    while(read(fd, &de, sizeof(de)) == sizeof(de)){
      if(de.inum == 0)
        continue;
      memmove(p, de.name, DIRSIZ);
      p[DIRSIZ] = 0;
      if(stat(buf, &st) < 0){
        printf("ls: cannot stat %s\n", buf);
        continue;
      }
      printf("%s %d %d %d\n", fmtname(buf), st.type, st.ino, (int) st.size);
    }
    break;
  }
  close(fd);
}

int
main(int argc, char *argv[])
{
  int i;

  if(argc < 2){
    ls(".");
    exit(0);
  }
  for(i=1; i<argc; i++)
    ls(argv[i]);
  exit(0);
}
```
## ../user/mkdir.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int
main(int argc, char *argv[])
{
  int i;

  if(argc < 2){
    fprintf(2, "Usage: mkdir files...\n");
    exit(1);
  }

  for(i = 1; i < argc; i++){
    if(mkdir(argv[i]) < 0){
      fprintf(2, "mkdir: %s failed to create\n", argv[i]);
      break;
    }
  }

  exit(0);
}
```
## ../user/printf.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

#include <stdarg.h>

static char digits[] = "0123456789ABCDEF";

static void
putc(int fd, char c)
{
  write(fd, &c, 1);
}

static void
printint(int fd, int xx, int base, int sgn)
{
  char buf[16];
  int i, neg;
  uint x;

  neg = 0;
  if(sgn && xx < 0){
    neg = 1;
    x = -xx;
  } else {
    x = xx;
  }

  i = 0;
  do{
    buf[i++] = digits[x % base];
  }while((x /= base) != 0);
  if(neg)
    buf[i++] = '-';

  while(--i >= 0)
    putc(fd, buf[i]);
}

static void
printptr(int fd, uint64 x) {
  int i;
  putc(fd, '0');
  putc(fd, 'x');
  for (i = 0; i < (sizeof(uint64) * 2); i++, x <<= 4)
    putc(fd, digits[x >> (sizeof(uint64) * 8 - 4)]);
}

// Print to the given fd. Only understands %d, %x, %p, %s.
void
vprintf(int fd, const char *fmt, va_list ap)
{
  char *s;
  int c0, c1, c2, i, state;

  state = 0;
  for(i = 0; fmt[i]; i++){
    c0 = fmt[i] & 0xff;
    if(state == 0){
      if(c0 == '%'){
        state = '%';
      } else {
        putc(fd, c0);
      }
    } else if(state == '%'){
      c1 = c2 = 0;
      if(c0) c1 = fmt[i+1] & 0xff;
      if(c1) c2 = fmt[i+2] & 0xff;
      if(c0 == 'd'){
        printint(fd, va_arg(ap, int), 10, 1);
      } else if(c0 == 'l' && c1 == 'd'){
        printint(fd, va_arg(ap, uint64), 10, 1);
        i += 1;
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'd'){
        printint(fd, va_arg(ap, uint64), 10, 1);
        i += 2;
      } else if(c0 == 'u'){
        printint(fd, va_arg(ap, int), 10, 0);
      } else if(c0 == 'l' && c1 == 'u'){
        printint(fd, va_arg(ap, uint64), 10, 0);
        i += 1;
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'u'){
        printint(fd, va_arg(ap, uint64), 10, 0);
        i += 2;
      } else if(c0 == 'x'){
        printint(fd, va_arg(ap, int), 16, 0);
      } else if(c0 == 'l' && c1 == 'x'){
        printint(fd, va_arg(ap, uint64), 16, 0);
        i += 1;
      } else if(c0 == 'l' && c1 == 'l' && c2 == 'x'){
        printint(fd, va_arg(ap, uint64), 16, 0);
        i += 2;
      } else if(c0 == 'p'){
        printptr(fd, va_arg(ap, uint64));
      } else if(c0 == 's'){
        if((s = va_arg(ap, char*)) == 0)
          s = "(null)";
        for(; *s; s++)
          putc(fd, *s);
      } else if(c0 == '%'){
        putc(fd, '%');
      } else {
        // Unknown % sequence.  Print it to draw attention.
        putc(fd, '%');
        putc(fd, c0);
      }

#if 0
      if(c == 'd'){
        printint(fd, va_arg(ap, int), 10, 1);
      } else if(c == 'l') {
        printint(fd, va_arg(ap, uint64), 10, 0);
      } else if(c == 'x') {
        printint(fd, va_arg(ap, int), 16, 0);
      } else if(c == 'p') {
        printptr(fd, va_arg(ap, uint64));
      } else if(c == 's'){
        s = va_arg(ap, char*);
        if(s == 0)
          s = "(null)";
        while(*s != 0){
          putc(fd, *s);
          s++;
        }
      } else if(c == 'c'){
        putc(fd, va_arg(ap, uint));
      } else if(c == '%'){
        putc(fd, c);
      } else {
        // Unknown % sequence.  Print it to draw attention.
        putc(fd, '%');
        putc(fd, c);
      }
#endif
      state = 0;
    }
  }
}

void
fprintf(int fd, const char *fmt, ...)
{
  va_list ap;

  va_start(ap, fmt);
  vprintf(fd, fmt, ap);
}

void
printf(const char *fmt, ...)
{
  va_list ap;

  va_start(ap, fmt);
  vprintf(1, fmt, ap);
}
```
## ../user/rm.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int
main(int argc, char *argv[])
{
  int i;

  if(argc < 2){
    fprintf(2, "Usage: rm files...\n");
    exit(1);
  }

  for(i = 1; i < argc; i++){
    if(unlink(argv[i]) < 0){
      fprintf(2, "rm: %s failed to delete\n", argv[i]);
      break;
    }
  }

  exit(0);
}
```
## ../user/sh.c 
```c
// Shell.

#include "kernel/types.h"
#include "user/user.h"
#include "kernel/fcntl.h"

// Parsed command representation
#define EXEC  1
#define REDIR 2
#define PIPE  3
#define LIST  4
#define BACK  5

#define MAXARGS 10

struct cmd {
  int type;
};

struct execcmd {
  int type;
  char *argv[MAXARGS];
  char *eargv[MAXARGS];
};

struct redircmd {
  int type;
  struct cmd *cmd;
  char *file;
  char *efile;
  int mode;
  int fd;
};

struct pipecmd {
  int type;
  struct cmd *left;
  struct cmd *right;
};

struct listcmd {
  int type;
  struct cmd *left;
  struct cmd *right;
};

struct backcmd {
  int type;
  struct cmd *cmd;
};

int fork1(void);  // Fork but panics on failure.
void panic(char*);
struct cmd *parsecmd(char*);
void runcmd(struct cmd*) __attribute__((noreturn));

// Execute cmd.  Never returns.
void
runcmd(struct cmd *cmd)
{
  int p[2];
  struct backcmd *bcmd;
  struct execcmd *ecmd;
  struct listcmd *lcmd;
  struct pipecmd *pcmd;
  struct redircmd *rcmd;

  if(cmd == 0)
    exit(1);

  switch(cmd->type){
  default:
    panic("runcmd");

  case EXEC:
    ecmd = (struct execcmd*)cmd;
    if(ecmd->argv[0] == 0)
      exit(1);
    exec(ecmd->argv[0], ecmd->argv);
    fprintf(2, "exec %s failed\n", ecmd->argv[0]);
    break;

  case REDIR:
    rcmd = (struct redircmd*)cmd;
    close(rcmd->fd);
    if(open(rcmd->file, rcmd->mode) < 0){
      fprintf(2, "open %s failed\n", rcmd->file);
      exit(1);
    }
    runcmd(rcmd->cmd);
    break;

  case LIST:
    lcmd = (struct listcmd*)cmd;
    if(fork1() == 0)
      runcmd(lcmd->left);
    wait(0);
    runcmd(lcmd->right);
    break;

  case PIPE:
    pcmd = (struct pipecmd*)cmd;
    if(pipe(p) < 0)
      panic("pipe");
    if(fork1() == 0){
      close(1);
      dup(p[1]);
      close(p[0]);
      close(p[1]);
      runcmd(pcmd->left);
    }
    if(fork1() == 0){
      close(0);
      dup(p[0]);
      close(p[0]);
      close(p[1]);
      runcmd(pcmd->right);
    }
    close(p[0]);
    close(p[1]);
    wait(0);
    wait(0);
    break;

  case BACK:
    bcmd = (struct backcmd*)cmd;
    if(fork1() == 0)
      runcmd(bcmd->cmd);
    break;
  }
  exit(0);
}

int
getcmd(char *buf, int nbuf)
{
  write(2, "$ ", 2);
  memset(buf, 0, nbuf);
  gets(buf, nbuf);
  if(buf[0] == 0) // EOF
    return -1;
  return 0;
}

int
main(void)
{
  static char buf[100];
  int fd;

  // Ensure that three file descriptors are open.
  while((fd = open("console", O_RDWR)) >= 0){
    if(fd >= 3){
      close(fd);
      break;
    }
  }

  // Read and run input commands.
  while(getcmd(buf, sizeof(buf)) >= 0){
    if(buf[0] == 'c' && buf[1] == 'd' && buf[2] == ' '){
      // Chdir must be called by the parent, not the child.
      buf[strlen(buf)-1] = 0;  // chop \n
      if(chdir(buf+3) < 0)
        fprintf(2, "cannot cd %s\n", buf+3);
      continue;
    }
    if(fork1() == 0)
      runcmd(parsecmd(buf));
    wait(0);
  }
  exit(0);
}

void
panic(char *s)
{
  fprintf(2, "%s\n", s);
  exit(1);
}

int
fork1(void)
{
  int pid;

  pid = fork();
  if(pid == -1)
    panic("fork");
  return pid;
}

//PAGEBREAK!
// Constructors

struct cmd*
execcmd(void)
{
  struct execcmd *cmd;

  cmd = malloc(sizeof(*cmd));
  memset(cmd, 0, sizeof(*cmd));
  cmd->type = EXEC;
  return (struct cmd*)cmd;
}

struct cmd*
redircmd(struct cmd *subcmd, char *file, char *efile, int mode, int fd)
{
  struct redircmd *cmd;

  cmd = malloc(sizeof(*cmd));
  memset(cmd, 0, sizeof(*cmd));
  cmd->type = REDIR;
  cmd->cmd = subcmd;
  cmd->file = file;
  cmd->efile = efile;
  cmd->mode = mode;
  cmd->fd = fd;
  return (struct cmd*)cmd;
}

struct cmd*
pipecmd(struct cmd *left, struct cmd *right)
{
  struct pipecmd *cmd;

  cmd = malloc(sizeof(*cmd));
  memset(cmd, 0, sizeof(*cmd));
  cmd->type = PIPE;
  cmd->left = left;
  cmd->right = right;
  return (struct cmd*)cmd;
}

struct cmd*
listcmd(struct cmd *left, struct cmd *right)
{
  struct listcmd *cmd;

  cmd = malloc(sizeof(*cmd));
  memset(cmd, 0, sizeof(*cmd));
  cmd->type = LIST;
  cmd->left = left;
  cmd->right = right;
  return (struct cmd*)cmd;
}

struct cmd*
backcmd(struct cmd *subcmd)
{
  struct backcmd *cmd;

  cmd = malloc(sizeof(*cmd));
  memset(cmd, 0, sizeof(*cmd));
  cmd->type = BACK;
  cmd->cmd = subcmd;
  return (struct cmd*)cmd;
}
//PAGEBREAK!
// Parsing

char whitespace[] = " \t\r\n\v";
char symbols[] = "<|>&;()";

int
gettoken(char **ps, char *es, char **q, char **eq)
{
  char *s;
  int ret;

  s = *ps;
  while(s < es && strchr(whitespace, *s))
    s++;
  if(q)
    *q = s;
  ret = *s;
  switch(*s){
  case 0:
    break;
  case '|':
  case '(':
  case ')':
  case ';':
  case '&':
  case '<':
    s++;
    break;
  case '>':
    s++;
    if(*s == '>'){
      ret = '+';
      s++;
    }
    break;
  default:
    ret = 'a';
    while(s < es && !strchr(whitespace, *s) && !strchr(symbols, *s))
      s++;
    break;
  }
  if(eq)
    *eq = s;

  while(s < es && strchr(whitespace, *s))
    s++;
  *ps = s;
  return ret;
}

int
peek(char **ps, char *es, char *toks)
{
  char *s;

  s = *ps;
  while(s < es && strchr(whitespace, *s))
    s++;
  *ps = s;
  return *s && strchr(toks, *s);
}

struct cmd *parseline(char**, char*);
struct cmd *parsepipe(char**, char*);
struct cmd *parseexec(char**, char*);
struct cmd *nulterminate(struct cmd*);

struct cmd*
parsecmd(char *s)
{
  char *es;
  struct cmd *cmd;

  es = s + strlen(s);
  cmd = parseline(&s, es);
  peek(&s, es, "");
  if(s != es){
    fprintf(2, "leftovers: %s\n", s);
    panic("syntax");
  }
  nulterminate(cmd);
  return cmd;
}

struct cmd*
parseline(char **ps, char *es)
{
  struct cmd *cmd;

  cmd = parsepipe(ps, es);
  while(peek(ps, es, "&")){
    gettoken(ps, es, 0, 0);
    cmd = backcmd(cmd);
  }
  if(peek(ps, es, ";")){
    gettoken(ps, es, 0, 0);
    cmd = listcmd(cmd, parseline(ps, es));
  }
  return cmd;
}

struct cmd*
parsepipe(char **ps, char *es)
{
  struct cmd *cmd;

  cmd = parseexec(ps, es);
  if(peek(ps, es, "|")){
    gettoken(ps, es, 0, 0);
    cmd = pipecmd(cmd, parsepipe(ps, es));
  }
  return cmd;
}

struct cmd*
parseredirs(struct cmd *cmd, char **ps, char *es)
{
  int tok;
  char *q, *eq;

  while(peek(ps, es, "<>")){
    tok = gettoken(ps, es, 0, 0);
    if(gettoken(ps, es, &q, &eq) != 'a')
      panic("missing file for redirection");
    switch(tok){
    case '<':
      cmd = redircmd(cmd, q, eq, O_RDONLY, 0);
      break;
    case '>':
      cmd = redircmd(cmd, q, eq, O_WRONLY|O_CREATE|O_TRUNC, 1);
      break;
    case '+':  // >>
      cmd = redircmd(cmd, q, eq, O_WRONLY|O_CREATE, 1);
      break;
    }
  }
  return cmd;
}

struct cmd*
parseblock(char **ps, char *es)
{
  struct cmd *cmd;

  if(!peek(ps, es, "("))
    panic("parseblock");
  gettoken(ps, es, 0, 0);
  cmd = parseline(ps, es);
  if(!peek(ps, es, ")"))
    panic("syntax - missing )");
  gettoken(ps, es, 0, 0);
  cmd = parseredirs(cmd, ps, es);
  return cmd;
}

struct cmd*
parseexec(char **ps, char *es)
{
  char *q, *eq;
  int tok, argc;
  struct execcmd *cmd;
  struct cmd *ret;

  if(peek(ps, es, "("))
    return parseblock(ps, es);

  ret = execcmd();
  cmd = (struct execcmd*)ret;

  argc = 0;
  ret = parseredirs(ret, ps, es);
  while(!peek(ps, es, "|)&;")){
    if((tok=gettoken(ps, es, &q, &eq)) == 0)
      break;
    if(tok != 'a')
      panic("syntax");
    cmd->argv[argc] = q;
    cmd->eargv[argc] = eq;
    argc++;
    if(argc >= MAXARGS)
      panic("too many args");
    ret = parseredirs(ret, ps, es);
  }
  cmd->argv[argc] = 0;
  cmd->eargv[argc] = 0;
  return ret;
}

// NUL-terminate all the counted strings.
struct cmd*
nulterminate(struct cmd *cmd)
{
  int i;
  struct backcmd *bcmd;
  struct execcmd *ecmd;
  struct listcmd *lcmd;
  struct pipecmd *pcmd;
  struct redircmd *rcmd;

  if(cmd == 0)
    return 0;

  switch(cmd->type){
  case EXEC:
    ecmd = (struct execcmd*)cmd;
    for(i=0; ecmd->argv[i]; i++)
      *ecmd->eargv[i] = 0;
    break;

  case REDIR:
    rcmd = (struct redircmd*)cmd;
    nulterminate(rcmd->cmd);
    *rcmd->efile = 0;
    break;

  case PIPE:
    pcmd = (struct pipecmd*)cmd;
    nulterminate(pcmd->left);
    nulterminate(pcmd->right);
    break;

  case LIST:
    lcmd = (struct listcmd*)cmd;
    nulterminate(lcmd->left);
    nulterminate(lcmd->right);
    break;

  case BACK:
    bcmd = (struct backcmd*)cmd;
    nulterminate(bcmd->cmd);
    break;
  }
  return cmd;
}
```
## ../user/stressfs.c 
```c
// Demonstrate that moving the "acquire" in iderw after the loop that
// appends to the idequeue results in a race.

// For this to work, you should also add a spin within iderw's
// idequeue traversal loop.  Adding the following demonstrated a panic
// after about 5 runs of stressfs in QEMU on a 2.1GHz CPU:
//    for (i = 0; i < 40000; i++)
//      asm volatile("");

#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"
#include "kernel/fcntl.h"

int
main(int argc, char *argv[])
{
  int fd, i;
  char path[] = "stressfs0";
  char data[512];

  printf("stressfs starting\n");
  memset(data, 'a', sizeof(data));

  for(i = 0; i < 4; i++)
    if(fork() > 0)
      break;

  printf("write %d\n", i);

  path[8] += i;
  fd = open(path, O_CREATE | O_RDWR);
  for(i = 0; i < 20; i++)
//    printf(fd, "%d\n", i);
    write(fd, data, sizeof(data));
  close(fd);

  printf("read\n");

  fd = open(path, O_RDONLY);
  for (i = 0; i < 20; i++)
    read(fd, data, sizeof(data));
  close(fd);

  wait(0);

  exit(0);
}
```
## ../user/ulib.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"

//
// wrapper so that it's OK if main() does not call exit().
//
void
start()
{
  extern int main();
  main();
  exit(0);
}

char*
strcpy(char *s, const char *t)
{
  char *os;

  os = s;
  while((*s++ = *t++) != 0)
    ;
  return os;
}

int
strcmp(const char *p, const char *q)
{
  while(*p && *p == *q)
    p++, q++;
  return (uchar)*p - (uchar)*q;
}

uint
strlen(const char *s)
{
  int n;

  for(n = 0; s[n]; n++)
    ;
  return n;
}

void*
memset(void *dst, int c, uint n)
{
  char *cdst = (char *) dst;
  int i;
  for(i = 0; i < n; i++){
    cdst[i] = c;
  }
  return dst;
}

char*
strchr(const char *s, char c)
{
  for(; *s; s++)
    if(*s == c)
      return (char*)s;
  return 0;
}

char*
gets(char *buf, int max)
{
  int i, cc;
  char c;

  for(i=0; i+1 < max; ){
    cc = read(0, &c, 1);
    if(cc < 1)
      break;
    buf[i++] = c;
    if(c == '\n' || c == '\r')
      break;
  }
  buf[i] = '\0';
  return buf;
}

int
stat(const char *n, struct stat *st)
{
  int fd;
  int r;

  fd = open(n, O_RDONLY);
  if(fd < 0)
    return -1;
  r = fstat(fd, st);
  close(fd);
  return r;
}

int
atoi(const char *s)
{
  int n;

  n = 0;
  while('0' <= *s && *s <= '9')
    n = n*10 + *s++ - '0';
  return n;
}

void*
memmove(void *vdst, const void *vsrc, int n)
{
  char *dst;
  const char *src;

  dst = vdst;
  src = vsrc;
  if (src > dst) {
    while(n-- > 0)
      *dst++ = *src++;
  } else {
    dst += n;
    src += n;
    while(n-- > 0)
      *--dst = *--src;
  }
  return vdst;
}

int
memcmp(const void *s1, const void *s2, uint n)
{
  const char *p1 = s1, *p2 = s2;
  while (n-- > 0) {
    if (*p1 != *p2) {
      return *p1 - *p2;
    }
    p1++;
    p2++;
  }
  return 0;
}

void *
memcpy(void *dst, const void *src, uint n)
{
  return memmove(dst, src, n);
}
```
## ../user/umalloc.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/param.h"

// Memory allocator by Kernighan and Ritchie,
// The C programming Language, 2nd ed.  Section 8.7.

typedef long Align;

union header {
  struct {
    union header *ptr;
    uint size;
  } s;
  Align x;
};

typedef union header Header;

static Header base;
static Header *freep;

void
free(void *ap)
{
  Header *bp, *p;

  bp = (Header*)ap - 1;
  for(p = freep; !(bp > p && bp < p->s.ptr); p = p->s.ptr)
    if(p >= p->s.ptr && (bp > p || bp < p->s.ptr))
      break;
  if(bp + bp->s.size == p->s.ptr){
    bp->s.size += p->s.ptr->s.size;
    bp->s.ptr = p->s.ptr->s.ptr;
  } else
    bp->s.ptr = p->s.ptr;
  if(p + p->s.size == bp){
    p->s.size += bp->s.size;
    p->s.ptr = bp->s.ptr;
  } else
    p->s.ptr = bp;
  freep = p;
}

static Header*
morecore(uint nu)
{
  char *p;
  Header *hp;

  if(nu < 4096)
    nu = 4096;
  p = sbrk(nu * sizeof(Header));
  if(p == (char*)-1)
    return 0;
  hp = (Header*)p;
  hp->s.size = nu;
  free((void*)(hp + 1));
  return freep;
}

void*
malloc(uint nbytes)
{
  Header *p, *prevp;
  uint nunits;

  nunits = (nbytes + sizeof(Header) - 1)/sizeof(Header) + 1;
  if((prevp = freep) == 0){
    base.s.ptr = freep = prevp = &base;
    base.s.size = 0;
  }
  for(p = prevp->s.ptr; ; prevp = p, p = p->s.ptr){
    if(p->s.size >= nunits){
      if(p->s.size == nunits)
        prevp->s.ptr = p->s.ptr;
      else {
        p->s.size -= nunits;
        p += p->s.size;
        p->s.size = nunits;
      }
      freep = prevp;
      return (void*)(p + 1);
    }
    if(p == freep)
      if((p = morecore(nunits)) == 0)
        return 0;
  }
}
```
## ../user/user.h 
```c
struct stat;

// system calls
int fork(void);
int exit(int) __attribute__((noreturn));
int wait(int*);
int pipe(int*);
int write(int, const void*, int);
int read(int, void*, int);
int close(int);
int kill(int);
int exec(const char*, char**);
int open(const char*, int);
int mknod(const char*, short, short);
int unlink(const char*);
int fstat(int fd, struct stat*);
int link(const char*, const char*);
int mkdir(const char*);
int chdir(const char*);
int dup(int);
int getpid(void);
char* sbrk(int);
int sleep(int);
int uptime(void);

// ulib.c
int stat(const char*, struct stat*);
char* strcpy(char*, const char*);
void *memmove(void*, const void*, int);
char* strchr(const char*, char c);
int strcmp(const char*, const char*);
void fprintf(int, const char*, ...) __attribute__ ((format (printf, 2, 3)));
void printf(const char*, ...) __attribute__ ((format (printf, 1, 2)));
char* gets(char*, int max);
uint strlen(const char*);
void* memset(void*, int, uint);
int atoi(const char*);
int memcmp(const void *, const void *, uint);
void *memcpy(void *, const void *, uint);

// umalloc.c
void* malloc(uint);
void free(void*);
```
## ../user/user.ld 
```c
OUTPUT_ARCH( "riscv" )

SECTIONS
{
 . = 0x0;
 
  .text : {
    *(.text .text.*)
  }

  .rodata : {
    . = ALIGN(16);
    *(.srodata .srodata.*) /* do not need to distinguish this from .rodata */
    . = ALIGN(16);
    *(.rodata .rodata.*)
  }

  .eh_frame : {
       *(.eh_frame)
       *(.eh_frame.*)
   }

  . = ALIGN(0x1000);
  .data : {
    . = ALIGN(16);
    *(.sdata .sdata.*) /* do not need to distinguish this from .data */
    . = ALIGN(16);
    *(.data .data.*)
  }

  .bss : {
    . = ALIGN(16);
    *(.sbss .sbss.*) /* do not need to distinguish this from .bss */
    . = ALIGN(16);
    *(.bss .bss.*)
  }

  PROVIDE(end = .);
}
```
## ../user/usertests.c 
```c
#include "kernel/param.h"
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"
#include "kernel/fcntl.h"
#include "kernel/syscall.h"
#include "kernel/memlayout.h"
#include "kernel/riscv.h"

//
// Tests xv6 system calls.  usertests without arguments runs them all
// and usertests <name> runs <name> test. The test runner creates for
// each test a process and based on the exit status of the process,
// the test runner reports "OK" or "FAILED".  Some tests result in
// kernel printing usertrap messages, which can be ignored if test
// prints "OK".
//

#define BUFSZ  ((MAXOPBLOCKS+2)*BSIZE)

char buf[BUFSZ];

//
// Section with tests that run fairly quickly.  Use -q if you want to
// run just those.  With -q usertests also runs the ones that take a
// fair of time.
//

// what if you pass ridiculous pointers to system calls
// that read user memory with copyin?
void
copyin(char *s)
{
  uint64 addrs[] = { 0x80000000LL, 0x3fffffe000, 0x3ffffff000, 0x4000000000,
                     0xffffffffffffffff };

  for(int ai = 0; ai < sizeof(addrs)/sizeof(addrs[0]); ai++){
    uint64 addr = addrs[ai];
    
    int fd = open("copyin1", O_CREATE|O_WRONLY);
    if(fd < 0){
      printf("open(copyin1) failed\n");
      exit(1);
    }
    int n = write(fd, (void*)addr, 8192);
    if(n >= 0){
      printf("write(fd, %p, 8192) returned %d, not -1\n", (void*)addr, n);
      exit(1);
    }
    close(fd);
    unlink("copyin1");
    
    n = write(1, (char*)addr, 8192);
    if(n > 0){
      printf("write(1, %p, 8192) returned %d, not -1 or 0\n", (void*)addr, n);
      exit(1);
    }
    
    int fds[2];
    if(pipe(fds) < 0){
      printf("pipe() failed\n");
      exit(1);
    }
    n = write(fds[1], (char*)addr, 8192);
    if(n > 0){
      printf("write(pipe, %p, 8192) returned %d, not -1 or 0\n", (void*)addr, n);
      exit(1);
    }
    close(fds[0]);
    close(fds[1]);
  }
}

// what if you pass ridiculous pointers to system calls
// that write user memory with copyout?
void
copyout(char *s)
{
  uint64 addrs[] = { 0LL, 0x80000000LL, 0x3fffffe000, 0x3ffffff000, 0x4000000000,
                     0xffffffffffffffff };

  for(int ai = 0; ai < sizeof(addrs)/sizeof(addrs[0]); ai++){
    uint64 addr = addrs[ai];

    int fd = open("README", 0);
    if(fd < 0){
      printf("open(README) failed\n");
      exit(1);
    }
    int n = read(fd, (void*)addr, 8192);
    if(n > 0){
      printf("read(fd, %p, 8192) returned %d, not -1 or 0\n", (void*)addr, n);
      exit(1);
    }
    close(fd);

    int fds[2];
    if(pipe(fds) < 0){
      printf("pipe() failed\n");
      exit(1);
    }
    n = write(fds[1], "x", 1);
    if(n != 1){
      printf("pipe write failed\n");
      exit(1);
    }
    n = read(fds[0], (void*)addr, 8192);
    if(n > 0){
      printf("read(pipe, %p, 8192) returned %d, not -1 or 0\n", (void*)addr, n);
      exit(1);
    }
    close(fds[0]);
    close(fds[1]);
  }
}

// what if you pass ridiculous string pointers to system calls?
void
copyinstr1(char *s)
{
  uint64 addrs[] = { 0x80000000LL, 0x3fffffe000, 0x3ffffff000, 0x4000000000,
                     0xffffffffffffffff };

  for(int ai = 0; ai < sizeof(addrs)/sizeof(addrs[0]); ai++){
    uint64 addr = addrs[ai];

    int fd = open((char *)addr, O_CREATE|O_WRONLY);
    if(fd >= 0){
      printf("open(%p) returned %d, not -1\n", (void*)addr, fd);
      exit(1);
    }
  }
}

// what if a string system call argument is exactly the size
// of the kernel buffer it is copied into, so that the null
// would fall just beyond the end of the kernel buffer?
void
copyinstr2(char *s)
{
  char b[MAXPATH+1];

  for(int i = 0; i < MAXPATH; i++)
    b[i] = 'x';
  b[MAXPATH] = '\0';
  
  int ret = unlink(b);
  if(ret != -1){
    printf("unlink(%s) returned %d, not -1\n", b, ret);
    exit(1);
  }

  int fd = open(b, O_CREATE | O_WRONLY);
  if(fd != -1){
    printf("open(%s) returned %d, not -1\n", b, fd);
    exit(1);
  }

  ret = link(b, b);
  if(ret != -1){
    printf("link(%s, %s) returned %d, not -1\n", b, b, ret);
    exit(1);
  }

  char *args[] = { "xx", 0 };
  ret = exec(b, args);
  if(ret != -1){
    printf("exec(%s) returned %d, not -1\n", b, fd);
    exit(1);
  }

  int pid = fork();
  if(pid < 0){
    printf("fork failed\n");
    exit(1);
  }
  if(pid == 0){
    static char big[PGSIZE+1];
    for(int i = 0; i < PGSIZE; i++)
      big[i] = 'x';
    big[PGSIZE] = '\0';
    char *args2[] = { big, big, big, 0 };
    ret = exec("echo", args2);
    if(ret != -1){
      printf("exec(echo, BIG) returned %d, not -1\n", fd);
      exit(1);
    }
    exit(747); // OK
  }

  int st = 0;
  wait(&st);
  if(st != 747){
    printf("exec(echo, BIG) succeeded, should have failed\n");
    exit(1);
  }
}

// what if a string argument crosses over the end of last user page?
void
copyinstr3(char *s)
{
  sbrk(8192);
  uint64 top = (uint64) sbrk(0);
  if((top % PGSIZE) != 0){
    sbrk(PGSIZE - (top % PGSIZE));
  }
  top = (uint64) sbrk(0);
  if(top % PGSIZE){
    printf("oops\n");
    exit(1);
  }

  char *b = (char *) (top - 1);
  *b = 'x';

  int ret = unlink(b);
  if(ret != -1){
    printf("unlink(%s) returned %d, not -1\n", b, ret);
    exit(1);
  }

  int fd = open(b, O_CREATE | O_WRONLY);
  if(fd != -1){
    printf("open(%s) returned %d, not -1\n", b, fd);
    exit(1);
  }

  ret = link(b, b);
  if(ret != -1){
    printf("link(%s, %s) returned %d, not -1\n", b, b, ret);
    exit(1);
  }

  char *args[] = { "xx", 0 };
  ret = exec(b, args);
  if(ret != -1){
    printf("exec(%s) returned %d, not -1\n", b, fd);
    exit(1);
  }
}

// See if the kernel refuses to read/write user memory that the
// application doesn't have anymore, because it returned it.
void
rwsbrk()
{
  int fd, n;
  
  uint64 a = (uint64) sbrk(8192);

  if(a == 0xffffffffffffffffLL) {
    printf("sbrk(rwsbrk) failed\n");
    exit(1);
  }
  
  if ((uint64) sbrk(-8192) ==  0xffffffffffffffffLL) {
    printf("sbrk(rwsbrk) shrink failed\n");
    exit(1);
  }

  fd = open("rwsbrk", O_CREATE|O_WRONLY);
  if(fd < 0){
    printf("open(rwsbrk) failed\n");
    exit(1);
  }
  n = write(fd, (void*)(a+4096), 1024);
  if(n >= 0){
    printf("write(fd, %p, 1024) returned %d, not -1\n", (void*)a+4096, n);
    exit(1);
  }
  close(fd);
  unlink("rwsbrk");

  fd = open("README", O_RDONLY);
  if(fd < 0){
    printf("open(rwsbrk) failed\n");
    exit(1);
  }
  n = read(fd, (void*)(a+4096), 10);
  if(n >= 0){
    printf("read(fd, %p, 10) returned %d, not -1\n", (void*)a+4096, n);
    exit(1);
  }
  close(fd);
  
  exit(0);
}

// test O_TRUNC.
void
truncate1(char *s)
{
  char buf[32];
  
  unlink("truncfile");
  int fd1 = open("truncfile", O_CREATE|O_WRONLY|O_TRUNC);
  write(fd1, "abcd", 4);
  close(fd1);

  int fd2 = open("truncfile", O_RDONLY);
  int n = read(fd2, buf, sizeof(buf));
  if(n != 4){
    printf("%s: read %d bytes, wanted 4\n", s, n);
    exit(1);
  }

  fd1 = open("truncfile", O_WRONLY|O_TRUNC);

  int fd3 = open("truncfile", O_RDONLY);
  n = read(fd3, buf, sizeof(buf));
  if(n != 0){
    printf("aaa fd3=%d\n", fd3);
    printf("%s: read %d bytes, wanted 0\n", s, n);
    exit(1);
  }

  n = read(fd2, buf, sizeof(buf));
  if(n != 0){
    printf("bbb fd2=%d\n", fd2);
    printf("%s: read %d bytes, wanted 0\n", s, n);
    exit(1);
  }
  
  write(fd1, "abcdef", 6);

  n = read(fd3, buf, sizeof(buf));
  if(n != 6){
    printf("%s: read %d bytes, wanted 6\n", s, n);
    exit(1);
  }

  n = read(fd2, buf, sizeof(buf));
  if(n != 2){
    printf("%s: read %d bytes, wanted 2\n", s, n);
    exit(1);
  }

  unlink("truncfile");

  close(fd1);
  close(fd2);
  close(fd3);
}

// write to an open FD whose file has just been truncated.
// this causes a write at an offset beyond the end of the file.
// such writes fail on xv6 (unlike POSIX) but at least
// they don't crash.
void
truncate2(char *s)
{
  unlink("truncfile");

  int fd1 = open("truncfile", O_CREATE|O_TRUNC|O_WRONLY);
  write(fd1, "abcd", 4);

  int fd2 = open("truncfile", O_TRUNC|O_WRONLY);

  int n = write(fd1, "x", 1);
  if(n != -1){
    printf("%s: write returned %d, expected -1\n", s, n);
    exit(1);
  }

  unlink("truncfile");
  close(fd1);
  close(fd2);
}

void
truncate3(char *s)
{
  int pid, xstatus;

  close(open("truncfile", O_CREATE|O_TRUNC|O_WRONLY));
  
  pid = fork();
  if(pid < 0){
    printf("%s: fork failed\n", s);
    exit(1);
  }

  if(pid == 0){
    for(int i = 0; i < 100; i++){
      char buf[32];
      int fd = open("truncfile", O_WRONLY);
      if(fd < 0){
        printf("%s: open failed\n", s);
        exit(1);
      }
      int n = write(fd, "1234567890", 10);
      if(n != 10){
        printf("%s: write got %d, expected 10\n", s, n);
        exit(1);
      }
      close(fd);
      fd = open("truncfile", O_RDONLY);
      read(fd, buf, sizeof(buf));
      close(fd);
    }
    exit(0);
  }

  for(int i = 0; i < 150; i++){
    int fd = open("truncfile", O_CREATE|O_WRONLY|O_TRUNC);
    if(fd < 0){
      printf("%s: open failed\n", s);
      exit(1);
    }
    int n = write(fd, "xxx", 3);
    if(n != 3){
      printf("%s: write got %d, expected 3\n", s, n);
      exit(1);
    }
    close(fd);
  }

  wait(&xstatus);
  unlink("truncfile");
  exit(xstatus);
}
  

// does chdir() call iput(p->cwd) in a transaction?
void
iputtest(char *s)
{
  if(mkdir("iputdir") < 0){
    printf("%s: mkdir failed\n", s);
    exit(1);
  }
  if(chdir("iputdir") < 0){
    printf("%s: chdir iputdir failed\n", s);
    exit(1);
  }
  if(unlink("../iputdir") < 0){
    printf("%s: unlink ../iputdir failed\n", s);
    exit(1);
  }
  if(chdir("/") < 0){
    printf("%s: chdir / failed\n", s);
    exit(1);
  }
}

// does exit() call iput(p->cwd) in a transaction?
void
exitiputtest(char *s)
{
  int pid, xstatus;

  pid = fork();
  if(pid < 0){
    printf("%s: fork failed\n", s);
    exit(1);
  }
  if(pid == 0){
    if(mkdir("iputdir") < 0){
      printf("%s: mkdir failed\n", s);
      exit(1);
    }
    if(chdir("iputdir") < 0){
      printf("%s: child chdir failed\n", s);
      exit(1);
    }
    if(unlink("../iputdir") < 0){
      printf("%s: unlink ../iputdir failed\n", s);
      exit(1);
    }
    exit(0);
  }
  wait(&xstatus);
  exit(xstatus);
}

// does the error path in open() for attempt to write a
// directory call iput() in a transaction?
// needs a hacked kernel that pauses just after the namei()
// call in sys_open():
//    if((ip = namei(path)) == 0)
//      return -1;
//    {
//      int i;
//      for(i = 0; i < 10000; i++)
//        yield();
//    }
void
openiputtest(char *s)
{
  int pid, xstatus;

  if(mkdir("oidir") < 0){
    printf("%s: mkdir oidir failed\n", s);
    exit(1);
  }
  pid = fork();
  if(pid < 0){
    printf("%s: fork failed\n", s);
    exit(1);
  }
  if(pid == 0){
    int fd = open("oidir", O_RDWR);
    if(fd >= 0){
      printf("%s: open directory for write succeeded\n", s);
      exit(1);
    }
    exit(0);
  }
  sleep(1);
  if(unlink("oidir") != 0){
    printf("%s: unlink failed\n", s);
    exit(1);
  }
  wait(&xstatus);
  exit(xstatus);
}

// simple file system tests

void
opentest(char *s)
{
  int fd;

  fd = open("echo", 0);
  if(fd < 0){
    printf("%s: open echo failed!\n", s);
    exit(1);
  }
  close(fd);
  fd = open("doesnotexist", 0);
  if(fd >= 0){
    printf("%s: open doesnotexist succeeded!\n", s);
    exit(1);
  }
}

void
writetest(char *s)
{
  int fd;
  int i;
  enum { N=100, SZ=10 };
  
  fd = open("small", O_CREATE|O_RDWR);
  if(fd < 0){
    printf("%s: error: creat small failed!\n", s);
    exit(1);
  }
  for(i = 0; i < N; i++){
    if(write(fd, "aaaaaaaaaa", SZ) != SZ){
      printf("%s: error: write aa %d new file failed\n", s, i);
      exit(1);
    }
    if(write(fd, "bbbbbbbbbb", SZ) != SZ){
      printf("%s: error: write bb %d new file failed\n", s, i);
      exit(1);
    }
  }
  close(fd);
  fd = open("small", O_RDONLY);
  if(fd < 0){
    printf("%s: error: open small failed!\n", s);
    exit(1);
  }
  i = read(fd, buf, N*SZ*2);
  if(i != N*SZ*2){
    printf("%s: read failed\n", s);
    exit(1);
  }
  close(fd);

  if(unlink("small") < 0){
    printf("%s: unlink small failed\n", s);
    exit(1);
  }
}

void
writebig(char *s)
{
  int i, fd, n;

  fd = open("big", O_CREATE|O_RDWR);
  if(fd < 0){
    printf("%s: error: creat big failed!\n", s);
    exit(1);
  }

  for(i = 0; i < MAXFILE; i++){
    ((int*)buf)[0] = i;
    if(write(fd, buf, BSIZE) != BSIZE){
      printf("%s: error: write big file failed i=%d\n", s, i);
      exit(1);
    }
  }

  close(fd);

  fd = open("big", O_RDONLY);
  if(fd < 0){
    printf("%s: error: open big failed!\n", s);
    exit(1);
  }

  n = 0;
  for(;;){
    i = read(fd, buf, BSIZE);
    if(i == 0){
      if(n != MAXFILE){
        printf("%s: read only %d blocks from big", s, n);
        exit(1);
      }
      break;
    } else if(i != BSIZE){
      printf("%s: read failed %d\n", s, i);
      exit(1);
    }
    if(((int*)buf)[0] != n){
      printf("%s: read content of block %d is %d\n", s,
             n, ((int*)buf)[0]);
      exit(1);
    }
    n++;
  }
  close(fd);
  if(unlink("big") < 0){
    printf("%s: unlink big failed\n", s);
    exit(1);
  }
}

// many creates, followed by unlink test
void
createtest(char *s)
{
  int i, fd;
  enum { N=52 };

  char name[3];
  name[0] = 'a';
  name[2] = '\0';
  for(i = 0; i < N; i++){
    name[1] = '0' + i;
    fd = open(name, O_CREATE|O_RDWR);
    close(fd);
  }
  name[0] = 'a';
  name[2] = '\0';
  for(i = 0; i < N; i++){
    name[1] = '0' + i;
    unlink(name);
  }
}

void dirtest(char *s)
{
  if(mkdir("dir0") < 0){
    printf("%s: mkdir failed\n", s);
    exit(1);
  }

  if(chdir("dir0") < 0){
    printf("%s: chdir dir0 failed\n", s);
    exit(1);
  }

  if(chdir("..") < 0){
    printf("%s: chdir .. failed\n", s);
    exit(1);
  }

  if(unlink("dir0") < 0){
    printf("%s: unlink dir0 failed\n", s);
    exit(1);
  }
}

void
exectest(char *s)
{
  int fd, xstatus, pid;
  char *echoargv[] = { "echo", "OK", 0 };
  char buf[3];

  unlink("echo-ok");
  pid = fork();
  if(pid < 0) {
     printf("%s: fork failed\n", s);
     exit(1);
  }
  if(pid == 0) {
    close(1);
    fd = open("echo-ok", O_CREATE|O_WRONLY);
    if(fd < 0) {
      printf("%s: create failed\n", s);
      exit(1);
    }
    if(fd != 1) {
      printf("%s: wrong fd\n", s);
      exit(1);
    }
    if(exec("echo", echoargv) < 0){
      printf("%s: exec echo failed\n", s);
      exit(1);
    }
    // won't get to here
  }
  if (wait(&xstatus) != pid) {
    printf("%s: wait failed!\n", s);
  }
  if(xstatus != 0)
    exit(xstatus);

  fd = open("echo-ok", O_RDONLY);
  if(fd < 0) {
    printf("%s: open failed\n", s);
    exit(1);
  }
  if (read(fd, buf, 2) != 2) {
    printf("%s: read failed\n", s);
    exit(1);
  }
  unlink("echo-ok");
  if(buf[0] == 'O' && buf[1] == 'K')
    exit(0);
  else {
    printf("%s: wrong output\n", s);
    exit(1);
  }

}

// simple fork and pipe read/write

void
pipe1(char *s)
{
  int fds[2], pid, xstatus;
  int seq, i, n, cc, total;
  enum { N=5, SZ=1033 };
  
  if(pipe(fds) != 0){
    printf("%s: pipe() failed\n", s);
    exit(1);
  }
  pid = fork();
  seq = 0;
  if(pid == 0){
    close(fds[0]);
    for(n = 0; n < N; n++){
      for(i = 0; i < SZ; i++)
        buf[i] = seq++;
      if(write(fds[1], buf, SZ) != SZ){
        printf("%s: pipe1 oops 1\n", s);
        exit(1);
      }
    }
    exit(0);
  } else if(pid > 0){
    close(fds[1]);
    total = 0;
    cc = 1;
    while((n = read(fds[0], buf, cc)) > 0){
      for(i = 0; i < n; i++){
        if((buf[i] & 0xff) != (seq++ & 0xff)){
          printf("%s: pipe1 oops 2\n", s);
          return;
        }
      }
      total += n;
      cc = cc * 2;
      if(cc > sizeof(buf))
        cc = sizeof(buf);
    }
    if(total != N * SZ){
      printf("%s: pipe1 oops 3 total %d\n", s, total);
      exit(1);
    }
    close(fds[0]);
    wait(&xstatus);
    exit(xstatus);
  } else {
    printf("%s: fork() failed\n", s);
    exit(1);
  }
}


// test if child is killed (status = -1)
void
killstatus(char *s)
{
  int xst;
  
  for(int i = 0; i < 100; i++){
    int pid1 = fork();
    if(pid1 < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(pid1 == 0){
      while(1) {
        getpid();
      }
      exit(0);
    }
    sleep(1);
    kill(pid1);
    wait(&xst);
    if(xst != -1) {
       printf("%s: status should be -1\n", s);
       exit(1);
    }
  }
  exit(0);
}

// meant to be run w/ at most two CPUs
void
preempt(char *s)
{
  int pid1, pid2, pid3;
  int pfds[2];

  pid1 = fork();
  if(pid1 < 0) {
    printf("%s: fork failed", s);
    exit(1);
  }
  if(pid1 == 0)
    for(;;)
      ;

  pid2 = fork();
  if(pid2 < 0) {
    printf("%s: fork failed\n", s);
    exit(1);
  }
  if(pid2 == 0)
    for(;;)
      ;

  pipe(pfds);
  pid3 = fork();
  if(pid3 < 0) {
     printf("%s: fork failed\n", s);
     exit(1);
  }
  if(pid3 == 0){
    close(pfds[0]);
    if(write(pfds[1], "x", 1) != 1)
      printf("%s: preempt write error", s);
    close(pfds[1]);
    for(;;)
      ;
  }

  close(pfds[1]);
  if(read(pfds[0], buf, sizeof(buf)) != 1){
    printf("%s: preempt read error", s);
    return;
  }
  close(pfds[0]);
  printf("kill... ");
  kill(pid1);
  kill(pid2);
  kill(pid3);
  printf("wait... ");
  wait(0);
  wait(0);
  wait(0);
}

// try to find any races between exit and wait
void
exitwait(char *s)
{
  int i, pid;

  for(i = 0; i < 100; i++){
    pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(pid){
      int xstate;
      if(wait(&xstate) != pid){
        printf("%s: wait wrong pid\n", s);
        exit(1);
      }
      if(i != xstate) {
        printf("%s: wait wrong exit status\n", s);
        exit(1);
      }
    } else {
      exit(i);
    }
  }
}

// try to find races in the reparenting
// code that handles a parent exiting
// when it still has live children.
void
reparent(char *s)
{
  int master_pid = getpid();
  for(int i = 0; i < 200; i++){
    int pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(pid){
      if(wait(0) != pid){
        printf("%s: wait wrong pid\n", s);
        exit(1);
      }
    } else {
      int pid2 = fork();
      if(pid2 < 0){
        kill(master_pid);
        exit(1);
      }
      exit(0);
    }
  }
  exit(0);
}

// what if two children exit() at the same time?
void
twochildren(char *s)
{
  for(int i = 0; i < 1000; i++){
    int pid1 = fork();
    if(pid1 < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(pid1 == 0){
      exit(0);
    } else {
      int pid2 = fork();
      if(pid2 < 0){
        printf("%s: fork failed\n", s);
        exit(1);
      }
      if(pid2 == 0){
        exit(0);
      } else {
        wait(0);
        wait(0);
      }
    }
  }
}

// concurrent forks to try to expose locking bugs.
void
forkfork(char *s)
{
  enum { N=2 };
  
  for(int i = 0; i < N; i++){
    int pid = fork();
    if(pid < 0){
      printf("%s: fork failed", s);
      exit(1);
    }
    if(pid == 0){
      for(int j = 0; j < 200; j++){
        int pid1 = fork();
        if(pid1 < 0){
          exit(1);
        }
        if(pid1 == 0){
          exit(0);
        }
        wait(0);
      }
      exit(0);
    }
  }

  int xstatus;
  for(int i = 0; i < N; i++){
    wait(&xstatus);
    if(xstatus != 0) {
      printf("%s: fork in child failed", s);
      exit(1);
    }
  }
}

void
forkforkfork(char *s)
{
  unlink("stopforking");

  int pid = fork();
  if(pid < 0){
    printf("%s: fork failed", s);
    exit(1);
  }
  if(pid == 0){
    while(1){
      int fd = open("stopforking", 0);
      if(fd >= 0){
        exit(0);
      }
      if(fork() < 0){
        close(open("stopforking", O_CREATE|O_RDWR));
      }
    }

    exit(0);
  }

  sleep(20); // two seconds
  close(open("stopforking", O_CREATE|O_RDWR));
  wait(0);
  sleep(10); // one second
}

// regression test. does reparent() violate the parent-then-child
// locking order when giving away a child to init, so that exit()
// deadlocks against init's wait()? also used to trigger a "panic:
// release" due to exit() releasing a different p->parent->lock than
// it acquired.
void
reparent2(char *s)
{
  for(int i = 0; i < 800; i++){
    int pid1 = fork();
    if(pid1 < 0){
      printf("fork failed\n");
      exit(1);
    }
    if(pid1 == 0){
      fork();
      fork();
      exit(0);
    }
    wait(0);
  }

  exit(0);
}

// allocate all mem, free it, and allocate again
void
mem(char *s)
{
  void *m1, *m2;
  int pid;

  if((pid = fork()) == 0){
    m1 = 0;
    while((m2 = malloc(10001)) != 0){
      *(char**)m2 = m1;
      m1 = m2;
    }
    while(m1){
      m2 = *(char**)m1;
      free(m1);
      m1 = m2;
    }
    m1 = malloc(1024*20);
    if(m1 == 0){
      printf("%s: couldn't allocate mem?!!\n", s);
      exit(1);
    }
    free(m1);
    exit(0);
  } else {
    int xstatus;
    wait(&xstatus);
    if(xstatus == -1){
      // probably page fault, so might be lazy lab,
      // so OK.
      exit(0);
    }
    exit(xstatus);
  }
}

// More file system tests

// two processes write to the same file descriptor
// is the offset shared? does inode locking work?
void
sharedfd(char *s)
{
  int fd, pid, i, n, nc, np;
  enum { N = 1000, SZ=10};
  char buf[SZ];

  unlink("sharedfd");
  fd = open("sharedfd", O_CREATE|O_RDWR);
  if(fd < 0){
    printf("%s: cannot open sharedfd for writing", s);
    exit(1);
  }
  pid = fork();
  memset(buf, pid==0?'c':'p', sizeof(buf));
  for(i = 0; i < N; i++){
    if(write(fd, buf, sizeof(buf)) != sizeof(buf)){
      printf("%s: write sharedfd failed\n", s);
      exit(1);
    }
  }
  if(pid == 0) {
    exit(0);
  } else {
    int xstatus;
    wait(&xstatus);
    if(xstatus != 0)
      exit(xstatus);
  }
  
  close(fd);
  fd = open("sharedfd", 0);
  if(fd < 0){
    printf("%s: cannot open sharedfd for reading\n", s);
    exit(1);
  }
  nc = np = 0;
  while((n = read(fd, buf, sizeof(buf))) > 0){
    for(i = 0; i < sizeof(buf); i++){
      if(buf[i] == 'c')
        nc++;
      if(buf[i] == 'p')
        np++;
    }
  }
  close(fd);
  unlink("sharedfd");
  if(nc == N*SZ && np == N*SZ){
    exit(0);
  } else {
    printf("%s: nc/np test fails\n", s);
    exit(1);
  }
}

// four processes write different files at the same
// time, to test block allocation.
void
fourfiles(char *s)
{
  int fd, pid, i, j, n, total, pi;
  char *names[] = { "f0", "f1", "f2", "f3" };
  char *fname;
  enum { N=12, NCHILD=4, SZ=500 };
  
  for(pi = 0; pi < NCHILD; pi++){
    fname = names[pi];
    unlink(fname);

    pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }

    if(pid == 0){
      fd = open(fname, O_CREATE | O_RDWR);
      if(fd < 0){
        printf("%s: create failed\n", s);
        exit(1);
      }

      memset(buf, '0'+pi, SZ);
      for(i = 0; i < N; i++){
        if((n = write(fd, buf, SZ)) != SZ){
          printf("write failed %d\n", n);
          exit(1);
        }
      }
      exit(0);
    }
  }

  int xstatus;
  for(pi = 0; pi < NCHILD; pi++){
    wait(&xstatus);
    if(xstatus != 0)
      exit(xstatus);
  }

  for(i = 0; i < NCHILD; i++){
    fname = names[i];
    fd = open(fname, 0);
    total = 0;
    while((n = read(fd, buf, sizeof(buf))) > 0){
      for(j = 0; j < n; j++){
        if(buf[j] != '0'+i){
          printf("%s: wrong char\n", s);
          exit(1);
        }
      }
      total += n;
    }
    close(fd);
    if(total != N*SZ){
      printf("wrong length %d\n", total);
      exit(1);
    }
    unlink(fname);
  }
}

// four processes create and delete different files in same directory
void
createdelete(char *s)
{
  enum { N = 20, NCHILD=4 };
  int pid, i, fd, pi;
  char name[32];

  for(pi = 0; pi < NCHILD; pi++){
    pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }

    if(pid == 0){
      name[0] = 'p' + pi;
      name[2] = '\0';
      for(i = 0; i < N; i++){
        name[1] = '0' + i;
        fd = open(name, O_CREATE | O_RDWR);
        if(fd < 0){
          printf("%s: create failed\n", s);
          exit(1);
        }
        close(fd);
        if(i > 0 && (i % 2 ) == 0){
          name[1] = '0' + (i / 2);
          if(unlink(name) < 0){
            printf("%s: unlink failed\n", s);
            exit(1);
          }
        }
      }
      exit(0);
    }
  }

  int xstatus;
  for(pi = 0; pi < NCHILD; pi++){
    wait(&xstatus);
    if(xstatus != 0)
      exit(1);
  }

  name[0] = name[1] = name[2] = 0;
  for(i = 0; i < N; i++){
    for(pi = 0; pi < NCHILD; pi++){
      name[0] = 'p' + pi;
      name[1] = '0' + i;
      fd = open(name, 0);
      if((i == 0 || i >= N/2) && fd < 0){
        printf("%s: oops createdelete %s didn't exist\n", s, name);
        exit(1);
      } else if((i >= 1 && i < N/2) && fd >= 0){
        printf("%s: oops createdelete %s did exist\n", s, name);
        exit(1);
      }
      if(fd >= 0)
        close(fd);
    }
  }

  for(i = 0; i < N; i++){
    for(pi = 0; pi < NCHILD; pi++){
      name[0] = 'p' + pi;
      name[1] = '0' + i;
      unlink(name);
    }
  }
}

// can I unlink a file and still read it?
void
unlinkread(char *s)
{
  enum { SZ = 5 };
  int fd, fd1;

  fd = open("unlinkread", O_CREATE | O_RDWR);
  if(fd < 0){
    printf("%s: create unlinkread failed\n", s);
    exit(1);
  }
  write(fd, "hello", SZ);
  close(fd);

  fd = open("unlinkread", O_RDWR);
  if(fd < 0){
    printf("%s: open unlinkread failed\n", s);
    exit(1);
  }
  if(unlink("unlinkread") != 0){
    printf("%s: unlink unlinkread failed\n", s);
    exit(1);
  }

  fd1 = open("unlinkread", O_CREATE | O_RDWR);
  write(fd1, "yyy", 3);
  close(fd1);

  if(read(fd, buf, sizeof(buf)) != SZ){
    printf("%s: unlinkread read failed", s);
    exit(1);
  }
  if(buf[0] != 'h'){
    printf("%s: unlinkread wrong data\n", s);
    exit(1);
  }
  if(write(fd, buf, 10) != 10){
    printf("%s: unlinkread write failed\n", s);
    exit(1);
  }
  close(fd);
  unlink("unlinkread");
}

void
linktest(char *s)
{
  enum { SZ = 5 };
  int fd;

  unlink("lf1");
  unlink("lf2");

  fd = open("lf1", O_CREATE|O_RDWR);
  if(fd < 0){
    printf("%s: create lf1 failed\n", s);
    exit(1);
  }
  if(write(fd, "hello", SZ) != SZ){
    printf("%s: write lf1 failed\n", s);
    exit(1);
  }
  close(fd);

  if(link("lf1", "lf2") < 0){
    printf("%s: link lf1 lf2 failed\n", s);
    exit(1);
  }
  unlink("lf1");

  if(open("lf1", 0) >= 0){
    printf("%s: unlinked lf1 but it is still there!\n", s);
    exit(1);
  }

  fd = open("lf2", 0);
  if(fd < 0){
    printf("%s: open lf2 failed\n", s);
    exit(1);
  }
  if(read(fd, buf, sizeof(buf)) != SZ){
    printf("%s: read lf2 failed\n", s);
    exit(1);
  }
  close(fd);

  if(link("lf2", "lf2") >= 0){
    printf("%s: link lf2 lf2 succeeded! oops\n", s);
    exit(1);
  }

  unlink("lf2");
  if(link("lf2", "lf1") >= 0){
    printf("%s: link non-existent succeeded! oops\n", s);
    exit(1);
  }

  if(link(".", "lf1") >= 0){
    printf("%s: link . lf1 succeeded! oops\n", s);
    exit(1);
  }
}

// test concurrent create/link/unlink of the same file
void
concreate(char *s)
{
  enum { N = 40 };
  char file[3];
  int i, pid, n, fd;
  char fa[N];
  struct {
    ushort inum;
    char name[DIRSIZ];
  } de;

  file[0] = 'C';
  file[2] = '\0';
  for(i = 0; i < N; i++){
    file[1] = '0' + i;
    unlink(file);
    pid = fork();
    if(pid && (i % 3) == 1){
      link("C0", file);
    } else if(pid == 0 && (i % 5) == 1){
      link("C0", file);
    } else {
      fd = open(file, O_CREATE | O_RDWR);
      if(fd < 0){
        printf("concreate create %s failed\n", file);
        exit(1);
      }
      close(fd);
    }
    if(pid == 0) {
      exit(0);
    } else {
      int xstatus;
      wait(&xstatus);
      if(xstatus != 0)
        exit(1);
    }
  }

  memset(fa, 0, sizeof(fa));
  fd = open(".", 0);
  n = 0;
  while(read(fd, &de, sizeof(de)) > 0){
    if(de.inum == 0)
      continue;
    if(de.name[0] == 'C' && de.name[2] == '\0'){
      i = de.name[1] - '0';
      if(i < 0 || i >= sizeof(fa)){
        printf("%s: concreate weird file %s\n", s, de.name);
        exit(1);
      }
      if(fa[i]){
        printf("%s: concreate duplicate file %s\n", s, de.name);
        exit(1);
      }
      fa[i] = 1;
      n++;
    }
  }
  close(fd);

  if(n != N){
    printf("%s: concreate not enough files in directory listing\n", s);
    exit(1);
  }

  for(i = 0; i < N; i++){
    file[1] = '0' + i;
    pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(((i % 3) == 0 && pid == 0) ||
       ((i % 3) == 1 && pid != 0)){
      close(open(file, 0));
      close(open(file, 0));
      close(open(file, 0));
      close(open(file, 0));
      close(open(file, 0));
      close(open(file, 0));
    } else {
      unlink(file);
      unlink(file);
      unlink(file);
      unlink(file);
      unlink(file);
      unlink(file);
    }
    if(pid == 0)
      exit(0);
    else
      wait(0);
  }
}

// another concurrent link/unlink/create test,
// to look for deadlocks.
void
linkunlink(char *s)
{
  int pid, i;

  unlink("x");
  pid = fork();
  if(pid < 0){
    printf("%s: fork failed\n", s);
    exit(1);
  }

  unsigned int x = (pid ? 1 : 97);
  for(i = 0; i < 100; i++){
    x = x * 1103515245 + 12345;
    if((x % 3) == 0){
      close(open("x", O_RDWR | O_CREATE));
    } else if((x % 3) == 1){
      link("cat", "x");
    } else {
      unlink("x");
    }
  }

  if(pid)
    wait(0);
  else
    exit(0);
}


void
subdir(char *s)
{
  int fd, cc;

  unlink("ff");
  if(mkdir("dd") != 0){
    printf("%s: mkdir dd failed\n", s);
    exit(1);
  }

  fd = open("dd/ff", O_CREATE | O_RDWR);
  if(fd < 0){
    printf("%s: create dd/ff failed\n", s);
    exit(1);
  }
  write(fd, "ff", 2);
  close(fd);

  if(unlink("dd") >= 0){
    printf("%s: unlink dd (non-empty dir) succeeded!\n", s);
    exit(1);
  }

  if(mkdir("/dd/dd") != 0){
    printf("%s: subdir mkdir dd/dd failed\n", s);
    exit(1);
  }

  fd = open("dd/dd/ff", O_CREATE | O_RDWR);
  if(fd < 0){
    printf("%s: create dd/dd/ff failed\n", s);
    exit(1);
  }
  write(fd, "FF", 2);
  close(fd);

  fd = open("dd/dd/../ff", 0);
  if(fd < 0){
    printf("%s: open dd/dd/../ff failed\n", s);
    exit(1);
  }
  cc = read(fd, buf, sizeof(buf));
  if(cc != 2 || buf[0] != 'f'){
    printf("%s: dd/dd/../ff wrong content\n", s);
    exit(1);
  }
  close(fd);

  if(link("dd/dd/ff", "dd/dd/ffff") != 0){
    printf("%s: link dd/dd/ff dd/dd/ffff failed\n", s);
    exit(1);
  }

  if(unlink("dd/dd/ff") != 0){
    printf("%s: unlink dd/dd/ff failed\n", s);
    exit(1);
  }
  if(open("dd/dd/ff", O_RDONLY) >= 0){
    printf("%s: open (unlinked) dd/dd/ff succeeded\n", s);
    exit(1);
  }

  if(chdir("dd") != 0){
    printf("%s: chdir dd failed\n", s);
    exit(1);
  }
  if(chdir("dd/../../dd") != 0){
    printf("%s: chdir dd/../../dd failed\n", s);
    exit(1);
  }
  if(chdir("dd/../../../dd") != 0){
    printf("%s: chdir dd/../../../dd failed\n", s);
    exit(1);
  }
  if(chdir("./..") != 0){
    printf("%s: chdir ./.. failed\n", s);
    exit(1);
  }

  fd = open("dd/dd/ffff", 0);
  if(fd < 0){
    printf("%s: open dd/dd/ffff failed\n", s);
    exit(1);
  }
  if(read(fd, buf, sizeof(buf)) != 2){
    printf("%s: read dd/dd/ffff wrong len\n", s);
    exit(1);
  }
  close(fd);

  if(open("dd/dd/ff", O_RDONLY) >= 0){
    printf("%s: open (unlinked) dd/dd/ff succeeded!\n", s);
    exit(1);
  }

  if(open("dd/ff/ff", O_CREATE|O_RDWR) >= 0){
    printf("%s: create dd/ff/ff succeeded!\n", s);
    exit(1);
  }
  if(open("dd/xx/ff", O_CREATE|O_RDWR) >= 0){
    printf("%s: create dd/xx/ff succeeded!\n", s);
    exit(1);
  }
  if(open("dd", O_CREATE) >= 0){
    printf("%s: create dd succeeded!\n", s);
    exit(1);
  }
  if(open("dd", O_RDWR) >= 0){
    printf("%s: open dd rdwr succeeded!\n", s);
    exit(1);
  }
  if(open("dd", O_WRONLY) >= 0){
    printf("%s: open dd wronly succeeded!\n", s);
    exit(1);
  }
  if(link("dd/ff/ff", "dd/dd/xx") == 0){
    printf("%s: link dd/ff/ff dd/dd/xx succeeded!\n", s);
    exit(1);
  }
  if(link("dd/xx/ff", "dd/dd/xx") == 0){
    printf("%s: link dd/xx/ff dd/dd/xx succeeded!\n", s);
    exit(1);
  }
  if(link("dd/ff", "dd/dd/ffff") == 0){
    printf("%s: link dd/ff dd/dd/ffff succeeded!\n", s);
    exit(1);
  }
  if(mkdir("dd/ff/ff") == 0){
    printf("%s: mkdir dd/ff/ff succeeded!\n", s);
    exit(1);
  }
  if(mkdir("dd/xx/ff") == 0){
    printf("%s: mkdir dd/xx/ff succeeded!\n", s);
    exit(1);
  }
  if(mkdir("dd/dd/ffff") == 0){
    printf("%s: mkdir dd/dd/ffff succeeded!\n", s);
    exit(1);
  }
  if(unlink("dd/xx/ff") == 0){
    printf("%s: unlink dd/xx/ff succeeded!\n", s);
    exit(1);
  }
  if(unlink("dd/ff/ff") == 0){
    printf("%s: unlink dd/ff/ff succeeded!\n", s);
    exit(1);
  }
  if(chdir("dd/ff") == 0){
    printf("%s: chdir dd/ff succeeded!\n", s);
    exit(1);
  }
  if(chdir("dd/xx") == 0){
    printf("%s: chdir dd/xx succeeded!\n", s);
    exit(1);
  }

  if(unlink("dd/dd/ffff") != 0){
    printf("%s: unlink dd/dd/ff failed\n", s);
    exit(1);
  }
  if(unlink("dd/ff") != 0){
    printf("%s: unlink dd/ff failed\n", s);
    exit(1);
  }
  if(unlink("dd") == 0){
    printf("%s: unlink non-empty dd succeeded!\n", s);
    exit(1);
  }
  if(unlink("dd/dd") < 0){
    printf("%s: unlink dd/dd failed\n", s);
    exit(1);
  }
  if(unlink("dd") < 0){
    printf("%s: unlink dd failed\n", s);
    exit(1);
  }
}

// test writes that are larger than the log.
void
bigwrite(char *s)
{
  int fd, sz;

  unlink("bigwrite");
  for(sz = 499; sz < (MAXOPBLOCKS+2)*BSIZE; sz += 471){
    fd = open("bigwrite", O_CREATE | O_RDWR);
    if(fd < 0){
      printf("%s: cannot create bigwrite\n", s);
      exit(1);
    }
    int i;
    for(i = 0; i < 2; i++){
      int cc = write(fd, buf, sz);
      if(cc != sz){
        printf("%s: write(%d) ret %d\n", s, sz, cc);
        exit(1);
      }
    }
    close(fd);
    unlink("bigwrite");
  }
}


void
bigfile(char *s)
{
  enum { N = 20, SZ=600 };
  int fd, i, total, cc;

  unlink("bigfile.dat");
  fd = open("bigfile.dat", O_CREATE | O_RDWR);
  if(fd < 0){
    printf("%s: cannot create bigfile", s);
    exit(1);
  }
  for(i = 0; i < N; i++){
    memset(buf, i, SZ);
    if(write(fd, buf, SZ) != SZ){
      printf("%s: write bigfile failed\n", s);
      exit(1);
    }
  }
  close(fd);

  fd = open("bigfile.dat", 0);
  if(fd < 0){
    printf("%s: cannot open bigfile\n", s);
    exit(1);
  }
  total = 0;
  for(i = 0; ; i++){
    cc = read(fd, buf, SZ/2);
    if(cc < 0){
      printf("%s: read bigfile failed\n", s);
      exit(1);
    }
    if(cc == 0)
      break;
    if(cc != SZ/2){
      printf("%s: short read bigfile\n", s);
      exit(1);
    }
    if(buf[0] != i/2 || buf[SZ/2-1] != i/2){
      printf("%s: read bigfile wrong data\n", s);
      exit(1);
    }
    total += cc;
  }
  close(fd);
  if(total != N*SZ){
    printf("%s: read bigfile wrong total\n", s);
    exit(1);
  }
  unlink("bigfile.dat");
}

void
fourteen(char *s)
{
  int fd;

  // DIRSIZ is 14.

  if(mkdir("12345678901234") != 0){
    printf("%s: mkdir 12345678901234 failed\n", s);
    exit(1);
  }
  if(mkdir("12345678901234/123456789012345") != 0){
    printf("%s: mkdir 12345678901234/123456789012345 failed\n", s);
    exit(1);
  }
  fd = open("123456789012345/123456789012345/123456789012345", O_CREATE);
  if(fd < 0){
    printf("%s: create 123456789012345/123456789012345/123456789012345 failed\n", s);
    exit(1);
  }
  close(fd);
  fd = open("12345678901234/12345678901234/12345678901234", 0);
  if(fd < 0){
    printf("%s: open 12345678901234/12345678901234/12345678901234 failed\n", s);
    exit(1);
  }
  close(fd);

  if(mkdir("12345678901234/12345678901234") == 0){
    printf("%s: mkdir 12345678901234/12345678901234 succeeded!\n", s);
    exit(1);
  }
  if(mkdir("123456789012345/12345678901234") == 0){
    printf("%s: mkdir 12345678901234/123456789012345 succeeded!\n", s);
    exit(1);
  }

  // clean up
  unlink("123456789012345/12345678901234");
  unlink("12345678901234/12345678901234");
  unlink("12345678901234/12345678901234/12345678901234");
  unlink("123456789012345/123456789012345/123456789012345");
  unlink("12345678901234/123456789012345");
  unlink("12345678901234");
}

void
rmdot(char *s)
{
  if(mkdir("dots") != 0){
    printf("%s: mkdir dots failed\n", s);
    exit(1);
  }
  if(chdir("dots") != 0){
    printf("%s: chdir dots failed\n", s);
    exit(1);
  }
  if(unlink(".") == 0){
    printf("%s: rm . worked!\n", s);
    exit(1);
  }
  if(unlink("..") == 0){
    printf("%s: rm .. worked!\n", s);
    exit(1);
  }
  if(chdir("/") != 0){
    printf("%s: chdir / failed\n", s);
    exit(1);
  }
  if(unlink("dots/.") == 0){
    printf("%s: unlink dots/. worked!\n", s);
    exit(1);
  }
  if(unlink("dots/..") == 0){
    printf("%s: unlink dots/.. worked!\n", s);
    exit(1);
  }
  if(unlink("dots") != 0){
    printf("%s: unlink dots failed!\n", s);
    exit(1);
  }
}

void
dirfile(char *s)
{
  int fd;

  fd = open("dirfile", O_CREATE);
  if(fd < 0){
    printf("%s: create dirfile failed\n", s);
    exit(1);
  }
  close(fd);
  if(chdir("dirfile") == 0){
    printf("%s: chdir dirfile succeeded!\n", s);
    exit(1);
  }
  fd = open("dirfile/xx", 0);
  if(fd >= 0){
    printf("%s: create dirfile/xx succeeded!\n", s);
    exit(1);
  }
  fd = open("dirfile/xx", O_CREATE);
  if(fd >= 0){
    printf("%s: create dirfile/xx succeeded!\n", s);
    exit(1);
  }
  if(mkdir("dirfile/xx") == 0){
    printf("%s: mkdir dirfile/xx succeeded!\n", s);
    exit(1);
  }
  if(unlink("dirfile/xx") == 0){
    printf("%s: unlink dirfile/xx succeeded!\n", s);
    exit(1);
  }
  if(link("README", "dirfile/xx") == 0){
    printf("%s: link to dirfile/xx succeeded!\n", s);
    exit(1);
  }
  if(unlink("dirfile") != 0){
    printf("%s: unlink dirfile failed!\n", s);
    exit(1);
  }

  fd = open(".", O_RDWR);
  if(fd >= 0){
    printf("%s: open . for writing succeeded!\n", s);
    exit(1);
  }
  fd = open(".", 0);
  if(write(fd, "x", 1) > 0){
    printf("%s: write . succeeded!\n", s);
    exit(1);
  }
  close(fd);
}

// test that iput() is called at the end of _namei().
// also tests empty file names.
void
iref(char *s)
{
  int i, fd;

  for(i = 0; i < NINODE + 1; i++){
    if(mkdir("irefd") != 0){
      printf("%s: mkdir irefd failed\n", s);
      exit(1);
    }
    if(chdir("irefd") != 0){
      printf("%s: chdir irefd failed\n", s);
      exit(1);
    }

    mkdir("");
    link("README", "");
    fd = open("", O_CREATE);
    if(fd >= 0)
      close(fd);
    fd = open("xx", O_CREATE);
    if(fd >= 0)
      close(fd);
    unlink("xx");
  }

  // clean up
  for(i = 0; i < NINODE + 1; i++){
    chdir("..");
    unlink("irefd");
  }

  chdir("/");
}

// test that fork fails gracefully
// the forktest binary also does this, but it runs out of proc entries first.
// inside the bigger usertests binary, we run out of memory first.
void
forktest(char *s)
{
  enum{ N = 1000 };
  int n, pid;

  for(n=0; n<N; n++){
    pid = fork();
    if(pid < 0)
      break;
    if(pid == 0)
      exit(0);
  }

  if (n == 0) {
    printf("%s: no fork at all!\n", s);
    exit(1);
  }

  if(n == N){
    printf("%s: fork claimed to work 1000 times!\n", s);
    exit(1);
  }

  for(; n > 0; n--){
    if(wait(0) < 0){
      printf("%s: wait stopped early\n", s);
      exit(1);
    }
  }

  if(wait(0) != -1){
    printf("%s: wait got too many\n", s);
    exit(1);
  }
}

void
sbrkbasic(char *s)
{
  enum { TOOMUCH=1024*1024*1024};
  int i, pid, xstatus;
  char *c, *a, *b;

  // does sbrk() return the expected failure value?
  pid = fork();
  if(pid < 0){
    printf("fork failed in sbrkbasic\n");
    exit(1);
  }
  if(pid == 0){
    a = sbrk(TOOMUCH);
    if(a == (char*)0xffffffffffffffffL){
      // it's OK if this fails.
      exit(0);
    }
    
    for(b = a; b < a+TOOMUCH; b += 4096){
      *b = 99;
    }
    
    // we should not get here! either sbrk(TOOMUCH)
    // should have failed, or (with lazy allocation)
    // a pagefault should have killed this process.
    exit(1);
  }

  wait(&xstatus);
  if(xstatus == 1){
    printf("%s: too much memory allocated!\n", s);
    exit(1);
  }

  // can one sbrk() less than a page?
  a = sbrk(0);
  for(i = 0; i < 5000; i++){
    b = sbrk(1);
    if(b != a){
      printf("%s: sbrk test failed %d %p %p\n", s, i, a, b);
      exit(1);
    }
    *b = 1;
    a = b + 1;
  }
  pid = fork();
  if(pid < 0){
    printf("%s: sbrk test fork failed\n", s);
    exit(1);
  }
  c = sbrk(1);
  c = sbrk(1);
  if(c != a + 1){
    printf("%s: sbrk test failed post-fork\n", s);
    exit(1);
  }
  if(pid == 0)
    exit(0);
  wait(&xstatus);
  exit(xstatus);
}

void
sbrkmuch(char *s)
{
  enum { BIG=100*1024*1024 };
  char *c, *oldbrk, *a, *lastaddr, *p;
  uint64 amt;

  oldbrk = sbrk(0);

  // can one grow address space to something big?
  a = sbrk(0);
  amt = BIG - (uint64)a;
  p = sbrk(amt);
  if (p != a) {
    printf("%s: sbrk test failed to grow big address space; enough phys mem?\n", s);
    exit(1);
  }

  // touch each page to make sure it exists.
  char *eee = sbrk(0);
  for(char *pp = a; pp < eee; pp += 4096)
    *pp = 1;

  lastaddr = (char*) (BIG-1);
  *lastaddr = 99;

  // can one de-allocate?
  a = sbrk(0);
  c = sbrk(-PGSIZE);
  if(c == (char*)0xffffffffffffffffL){
    printf("%s: sbrk could not deallocate\n", s);
    exit(1);
  }
  c = sbrk(0);
  if(c != a - PGSIZE){
    printf("%s: sbrk deallocation produced wrong address, a %p c %p\n", s, a, c);
    exit(1);
  }

  // can one re-allocate that page?
  a = sbrk(0);
  c = sbrk(PGSIZE);
  if(c != a || sbrk(0) != a + PGSIZE){
    printf("%s: sbrk re-allocation failed, a %p c %p\n", s, a, c);
    exit(1);
  }
  if(*lastaddr == 99){
    // should be zero
    printf("%s: sbrk de-allocation didn't really deallocate\n", s);
    exit(1);
  }

  a = sbrk(0);
  c = sbrk(-(sbrk(0) - oldbrk));
  if(c != a){
    printf("%s: sbrk downsize failed, a %p c %p\n", s, a, c);
    exit(1);
  }
}

// can we read the kernel's memory?
void
kernmem(char *s)
{
  char *a;
  int pid;

  for(a = (char*)(KERNBASE); a < (char*) (KERNBASE+2000000); a += 50000){
    pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(pid == 0){
      printf("%s: oops could read %p = %x\n", s, a, *a);
      exit(1);
    }
    int xstatus;
    wait(&xstatus);
    if(xstatus != -1)  // did kernel kill child?
      exit(1);
  }
}

// user code should not be able to write to addresses above MAXVA.
void
MAXVAplus(char *s)
{
  volatile uint64 a = MAXVA;
  for( ; a != 0; a <<= 1){
    int pid;
    pid = fork();
    if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    if(pid == 0){
      *(char*)a = 99;
      printf("%s: oops wrote %p\n", s, (void*)a);
      exit(1);
    }
    int xstatus;
    wait(&xstatus);
    if(xstatus != -1)  // did kernel kill child?
      exit(1);
  }
}

// if we run the system out of memory, does it clean up the last
// failed allocation?
void
sbrkfail(char *s)
{
  enum { BIG=100*1024*1024 };
  int i, xstatus;
  int fds[2];
  char scratch;
  char *c, *a;
  int pids[10];
  int pid;
 
  if(pipe(fds) != 0){
    printf("%s: pipe() failed\n", s);
    exit(1);
  }
  for(i = 0; i < sizeof(pids)/sizeof(pids[0]); i++){
    if((pids[i] = fork()) == 0){
      // allocate a lot of memory
      sbrk(BIG - (uint64)sbrk(0));
      write(fds[1], "x", 1);
      // sit around until killed
      for(;;) sleep(1000);
    }
    if(pids[i] != -1)
      read(fds[0], &scratch, 1);
  }

  // if those failed allocations freed up the pages they did allocate,
  // we'll be able to allocate here
  c = sbrk(PGSIZE);
  for(i = 0; i < sizeof(pids)/sizeof(pids[0]); i++){
    if(pids[i] == -1)
      continue;
    kill(pids[i]);
    wait(0);
  }
  if(c == (char*)0xffffffffffffffffL){
    printf("%s: failed sbrk leaked memory\n", s);
    exit(1);
  }

  // test running fork with the above allocated page 
  pid = fork();
  if(pid < 0){
    printf("%s: fork failed\n", s);
    exit(1);
  }
  if(pid == 0){
    // allocate a lot of memory.
    // this should produce a page fault,
    // and thus not complete.
    a = sbrk(0);
    sbrk(10*BIG);
    int n = 0;
    for (i = 0; i < 10*BIG; i += PGSIZE) {
      n += *(a+i);
    }
    // print n so the compiler doesn't optimize away
    // the for loop.
    printf("%s: allocate a lot of memory succeeded %d\n", s, n);
    exit(1);
  }
  wait(&xstatus);
  if(xstatus != -1 && xstatus != 2)
    exit(1);
}

  
// test reads/writes from/to allocated memory
void
sbrkarg(char *s)
{
  char *a;
  int fd, n;

  a = sbrk(PGSIZE);
  fd = open("sbrk", O_CREATE|O_WRONLY);
  unlink("sbrk");
  if(fd < 0)  {
    printf("%s: open sbrk failed\n", s);
    exit(1);
  }
  if ((n = write(fd, a, PGSIZE)) < 0) {
    printf("%s: write sbrk failed\n", s);
    exit(1);
  }
  close(fd);

  // test writes to allocated memory
  a = sbrk(PGSIZE);
  if(pipe((int *) a) != 0){
    printf("%s: pipe() failed\n", s);
    exit(1);
  } 
}

void
validatetest(char *s)
{
  int hi;
  uint64 p;

  hi = 1100*1024;
  for(p = 0; p <= (uint)hi; p += PGSIZE){
    // try to crash the kernel by passing in a bad string pointer
    if(link("nosuchfile", (char*)p) != -1){
      printf("%s: link should not succeed\n", s);
      exit(1);
    }
  }
}

// does uninitialized data start out zero?
char uninit[10000];
void
bsstest(char *s)
{
  int i;

  for(i = 0; i < sizeof(uninit); i++){
    if(uninit[i] != '\0'){
      printf("%s: bss test failed\n", s);
      exit(1);
    }
  }
}

// does exec return an error if the arguments
// are larger than a page? or does it write
// below the stack and wreck the instructions/data?
void
bigargtest(char *s)
{
  int pid, fd, xstatus;

  unlink("bigarg-ok");
  pid = fork();
  if(pid == 0){
    static char *args[MAXARG];
    int i;
    char big[400];
    memset(big, ' ', sizeof(big));
    big[sizeof(big)-1] = '\0';
    for(i = 0; i < MAXARG-1; i++)
      args[i] = big;
    args[MAXARG-1] = 0;
    // this exec() should fail (and return) because the
    // arguments are too large.
    exec("echo", args);
    fd = open("bigarg-ok", O_CREATE);
    close(fd);
    exit(0);
  } else if(pid < 0){
    printf("%s: bigargtest: fork failed\n", s);
    exit(1);
  }
  
  wait(&xstatus);
  if(xstatus != 0)
    exit(xstatus);
  fd = open("bigarg-ok", 0);
  if(fd < 0){
    printf("%s: bigarg test failed!\n", s);
    exit(1);
  }
  close(fd);
}

// what happens when the file system runs out of blocks?
// answer: balloc panics, so this test is not useful.
void
fsfull()
{
  int nfiles;
  int fsblocks = 0;

  printf("fsfull test\n");

  for(nfiles = 0; ; nfiles++){
    char name[64];
    name[0] = 'f';
    name[1] = '0' + nfiles / 1000;
    name[2] = '0' + (nfiles % 1000) / 100;
    name[3] = '0' + (nfiles % 100) / 10;
    name[4] = '0' + (nfiles % 10);
    name[5] = '\0';
    printf("writing %s\n", name);
    int fd = open(name, O_CREATE|O_RDWR);
    if(fd < 0){
      printf("open %s failed\n", name);
      break;
    }
    int total = 0;
    while(1){
      int cc = write(fd, buf, BSIZE);
      if(cc < BSIZE)
        break;
      total += cc;
      fsblocks++;
    }
    printf("wrote %d bytes\n", total);
    close(fd);
    if(total == 0)
      break;
  }

  while(nfiles >= 0){
    char name[64];
    name[0] = 'f';
    name[1] = '0' + nfiles / 1000;
    name[2] = '0' + (nfiles % 1000) / 100;
    name[3] = '0' + (nfiles % 100) / 10;
    name[4] = '0' + (nfiles % 10);
    name[5] = '\0';
    unlink(name);
    nfiles--;
  }

  printf("fsfull test finished\n");
}

void argptest(char *s)
{
  int fd;
  fd = open("init", O_RDONLY);
  if (fd < 0) {
    printf("%s: open failed\n", s);
    exit(1);
  }
  read(fd, sbrk(0) - 1, -1);
  close(fd);
}

// check that there's an invalid page beneath
// the user stack, to catch stack overflow.
void
stacktest(char *s)
{
  int pid;
  int xstatus;
  
  pid = fork();
  if(pid == 0) {
    char *sp = (char *) r_sp();
    sp -= USERSTACK*PGSIZE;
    // the *sp should cause a trap.
    printf("%s: stacktest: read below stack %d\n", s, *sp);
    exit(1);
  } else if(pid < 0){
    printf("%s: fork failed\n", s);
    exit(1);
  }
  wait(&xstatus);
  if(xstatus == -1)  // kernel killed child?
    exit(0);
  else
    exit(xstatus);
}

// check that writes to a few forbidden addresses
// cause a fault, e.g. process's text and TRAMPOLINE.
void
nowrite(char *s)
{
  int pid;
  int xstatus;
  uint64 addrs[] = { 0, 0x80000000LL, 0x3fffffe000, 0x3ffffff000, 0x4000000000,
                     0xffffffffffffffff };
  
  for(int ai = 0; ai < sizeof(addrs)/sizeof(addrs[0]); ai++){
    pid = fork();
    if(pid == 0) {
      volatile int *addr = (int *) addrs[ai];
      *addr = 10;
      printf("%s: write to %p did not fail!\n", s, addr);
      exit(0);
    } else if(pid < 0){
      printf("%s: fork failed\n", s);
      exit(1);
    }
    wait(&xstatus);
    if(xstatus == 0){
      // kernel did not kill child!
      exit(1);
    }
  }
  exit(0);
}

// regression test. copyin(), copyout(), and copyinstr() used to cast
// the virtual page address to uint, which (with certain wild system
// call arguments) resulted in a kernel page faults.
void *big = (void*) 0xeaeb0b5b00002f5e;
void
pgbug(char *s)
{
  char *argv[1];
  argv[0] = 0;
  exec(big, argv);
  pipe(big);

  exit(0);
}

// regression test. does the kernel panic if a process sbrk()s its
// size to be less than a page, or zero, or reduces the break by an
// amount too small to cause a page to be freed?
void
sbrkbugs(char *s)
{
  int pid = fork();
  if(pid < 0){
    printf("fork failed\n");
    exit(1);
  }
  if(pid == 0){
    int sz = (uint64) sbrk(0);
    // free all user memory; there used to be a bug that
    // would not adjust p->sz correctly in this case,
    // causing exit() to panic.
    sbrk(-sz);
    // user page fault here.
    exit(0);
  }
  wait(0);

  pid = fork();
  if(pid < 0){
    printf("fork failed\n");
    exit(1);
  }
  if(pid == 0){
    int sz = (uint64) sbrk(0);
    // set the break to somewhere in the very first
    // page; there used to be a bug that would incorrectly
    // free the first page.
    sbrk(-(sz - 3500));
    exit(0);
  }
  wait(0);

  pid = fork();
  if(pid < 0){
    printf("fork failed\n");
    exit(1);
  }
  if(pid == 0){
    // set the break in the middle of a page.
    sbrk((10*4096 + 2048) - (uint64)sbrk(0));

    // reduce the break a bit, but not enough to
    // cause a page to be freed. this used to cause
    // a panic.
    sbrk(-10);

    exit(0);
  }
  wait(0);

  exit(0);
}

// if process size was somewhat more than a page boundary, and then
// shrunk to be somewhat less than that page boundary, can the kernel
// still copyin() from addresses in the last page?
void
sbrklast(char *s)
{
  uint64 top = (uint64) sbrk(0);
  if((top % 4096) != 0)
    sbrk(4096 - (top % 4096));
  sbrk(4096);
  sbrk(10);
  sbrk(-20);
  top = (uint64) sbrk(0);
  char *p = (char *) (top - 64);
  p[0] = 'x';
  p[1] = '\0';
  int fd = open(p, O_RDWR|O_CREATE);
  write(fd, p, 1);
  close(fd);
  fd = open(p, O_RDWR);
  p[0] = '\0';
  read(fd, p, 1);
  if(p[0] != 'x')
    exit(1);
}


// does sbrk handle signed int32 wrap-around with
// negative arguments?
void
sbrk8000(char *s)
{
  sbrk(0x80000004);
  volatile char *top = sbrk(0);
  *(top-1) = *(top-1) + 1;
}



// regression test. test whether exec() leaks memory if one of the
// arguments is invalid. the test passes if the kernel doesn't panic.
void
badarg(char *s)
{
  for(int i = 0; i < 50000; i++){
    char *argv[2];
    argv[0] = (char*)0xffffffff;
    argv[1] = 0;
    exec("echo", argv);
  }
  
  exit(0);
}

struct test {
  void (*f)(char *);
  char *s;
} quicktests[] = {
  {copyin, "copyin"},
  {copyout, "copyout"},
  {copyinstr1, "copyinstr1"},
  {copyinstr2, "copyinstr2"},
  {copyinstr3, "copyinstr3"},
  {rwsbrk, "rwsbrk" },
  {truncate1, "truncate1"},
  {truncate2, "truncate2"},
  {truncate3, "truncate3"},
  {openiputtest, "openiput"},
  {exitiputtest, "exitiput"},
  {iputtest, "iput"},
  {opentest, "opentest"},
  {writetest, "writetest"},
  {writebig, "writebig"},
  {createtest, "createtest"},
  {dirtest, "dirtest"},
  {exectest, "exectest"},
  {pipe1, "pipe1"},
  {killstatus, "killstatus"},
  {preempt, "preempt"},
  {exitwait, "exitwait"},
  {reparent, "reparent" },
  {twochildren, "twochildren"},
  {forkfork, "forkfork"},
  {forkforkfork, "forkforkfork"},
  {reparent2, "reparent2"},
  {mem, "mem"},
  {sharedfd, "sharedfd"},
  {fourfiles, "fourfiles"},
  {createdelete, "createdelete"},
  {unlinkread, "unlinkread"},
  {linktest, "linktest"},
  {concreate, "concreate"},
  {linkunlink, "linkunlink"},
  {subdir, "subdir"},
  {bigwrite, "bigwrite"},
  {bigfile, "bigfile"},
  {fourteen, "fourteen"},
  {rmdot, "rmdot"},
  {dirfile, "dirfile"},
  {iref, "iref"},
  {forktest, "forktest"},
  {sbrkbasic, "sbrkbasic"},
  {sbrkmuch, "sbrkmuch"},
  {kernmem, "kernmem"},
  {MAXVAplus, "MAXVAplus"},
  {sbrkfail, "sbrkfail"},
  {sbrkarg, "sbrkarg"},
  {validatetest, "validatetest"},
  {bsstest, "bsstest"},
  {bigargtest, "bigargtest"},
  {argptest, "argptest"},
  {stacktest, "stacktest"},
  {nowrite, "nowrite"},
  {pgbug, "pgbug" },
  {sbrkbugs, "sbrkbugs" },
  {sbrklast, "sbrklast"},
  {sbrk8000, "sbrk8000"},
  {badarg, "badarg" },

  { 0, 0},
};

//
// Section with tests that take a fair bit of time
//

// directory that uses indirect blocks
void
bigdir(char *s)
{
  enum { N = 500 };
  int i, fd;
  char name[10];

  unlink("bd");

  fd = open("bd", O_CREATE);
  if(fd < 0){
    printf("%s: bigdir create failed\n", s);
    exit(1);
  }
  close(fd);

  for(i = 0; i < N; i++){
    name[0] = 'x';
    name[1] = '0' + (i / 64);
    name[2] = '0' + (i % 64);
    name[3] = '\0';
    if(link("bd", name) != 0){
      printf("%s: bigdir i=%d link(bd, %s) failed\n", s, i, name);
      exit(1);
    }
  }

  unlink("bd");
  for(i = 0; i < N; i++){
    name[0] = 'x';
    name[1] = '0' + (i / 64);
    name[2] = '0' + (i % 64);
    name[3] = '\0';
    if(unlink(name) != 0){
      printf("%s: bigdir unlink failed", s);
      exit(1);
    }
  }
}

// concurrent writes to try to provoke deadlock in the virtio disk
// driver.
void
manywrites(char *s)
{
  int nchildren = 4;
  int howmany = 30; // increase to look for deadlock
  
  for(int ci = 0; ci < nchildren; ci++){
    int pid = fork();
    if(pid < 0){
      printf("fork failed\n");
      exit(1);
    }

    if(pid == 0){
      char name[3];
      name[0] = 'b';
      name[1] = 'a' + ci;
      name[2] = '\0';
      unlink(name);
      
      for(int iters = 0; iters < howmany; iters++){
        for(int i = 0; i < ci+1; i++){
          int fd = open(name, O_CREATE | O_RDWR);
          if(fd < 0){
            printf("%s: cannot create %s\n", s, name);
            exit(1);
          }
          int sz = sizeof(buf);
          int cc = write(fd, buf, sz);
          if(cc != sz){
            printf("%s: write(%d) ret %d\n", s, sz, cc);
            exit(1);
          }
          close(fd);
        }
        unlink(name);
      }

      unlink(name);
      exit(0);
    }
  }

  for(int ci = 0; ci < nchildren; ci++){
    int st = 0;
    wait(&st);
    if(st != 0)
      exit(st);
  }
  exit(0);
}

// regression test. does write() with an invalid buffer pointer cause
// a block to be allocated for a file that is then not freed when the
// file is deleted? if the kernel has this bug, it will panic: balloc:
// out of blocks. assumed_free may need to be raised to be more than
// the number of free blocks. this test takes a long time.
void
badwrite(char *s)
{
  int assumed_free = 600;
  
  unlink("junk");
  for(int i = 0; i < assumed_free; i++){
    int fd = open("junk", O_CREATE|O_WRONLY);
    if(fd < 0){
      printf("open junk failed\n");
      exit(1);
    }
    write(fd, (char*)0xffffffffffL, 1);
    close(fd);
    unlink("junk");
  }

  int fd = open("junk", O_CREATE|O_WRONLY);
  if(fd < 0){
    printf("open junk failed\n");
    exit(1);
  }
  if(write(fd, "x", 1) != 1){
    printf("write failed\n");
    exit(1);
  }
  close(fd);
  unlink("junk");

  exit(0);
}

// test the exec() code that cleans up if it runs out
// of memory. it's really a test that such a condition
// doesn't cause a panic.
void
execout(char *s)
{
  for(int avail = 0; avail < 15; avail++){
    int pid = fork();
    if(pid < 0){
      printf("fork failed\n");
      exit(1);
    } else if(pid == 0){
      // allocate all of memory.
      while(1){
        uint64 a = (uint64) sbrk(4096);
        if(a == 0xffffffffffffffffLL)
          break;
        *(char*)(a + 4096 - 1) = 1;
      }

      // free a few pages, in order to let exec() make some
      // progress.
      for(int i = 0; i < avail; i++)
        sbrk(-4096);
      
      close(1);
      char *args[] = { "echo", "x", 0 };
      exec("echo", args);
      exit(0);
    } else {
      wait((int*)0);
    }
  }

  exit(0);
}

// can the kernel tolerate running out of disk space?
void
diskfull(char *s)
{
  int fi;
  int done = 0;

  unlink("diskfulldir");
  
  for(fi = 0; done == 0 && '0' + fi < 0177; fi++){
    char name[32];
    name[0] = 'b';
    name[1] = 'i';
    name[2] = 'g';
    name[3] = '0' + fi;
    name[4] = '\0';
    unlink(name);
    int fd = open(name, O_CREATE|O_RDWR|O_TRUNC);
    if(fd < 0){
      // oops, ran out of inodes before running out of blocks.
      printf("%s: could not create file %s\n", s, name);
      done = 1;
      break;
    }
    for(int i = 0; i < MAXFILE; i++){
      char buf[BSIZE];
      if(write(fd, buf, BSIZE) != BSIZE){
        done = 1;
        close(fd);
        break;
      }
    }
    close(fd);
  }

  // now that there are no free blocks, test that dirlink()
  // merely fails (doesn't panic) if it can't extend
  // directory content. one of these file creations
  // is expected to fail.
  int nzz = 128;
  for(int i = 0; i < nzz; i++){
    char name[32];
    name[0] = 'z';
    name[1] = 'z';
    name[2] = '0' + (i / 32);
    name[3] = '0' + (i % 32);
    name[4] = '\0';
    unlink(name);
    int fd = open(name, O_CREATE|O_RDWR|O_TRUNC);
    if(fd < 0)
      break;
    close(fd);
  }

  // this mkdir() is expected to fail.
  if(mkdir("diskfulldir") == 0)
    printf("%s: mkdir(diskfulldir) unexpectedly succeeded!\n", s);

  unlink("diskfulldir");

  for(int i = 0; i < nzz; i++){
    char name[32];
    name[0] = 'z';
    name[1] = 'z';
    name[2] = '0' + (i / 32);
    name[3] = '0' + (i % 32);
    name[4] = '\0';
    unlink(name);
  }

  for(int i = 0; '0' + i < 0177; i++){
    char name[32];
    name[0] = 'b';
    name[1] = 'i';
    name[2] = 'g';
    name[3] = '0' + i;
    name[4] = '\0';
    unlink(name);
  }
}

void
outofinodes(char *s)
{
  int nzz = 32*32;
  for(int i = 0; i < nzz; i++){
    char name[32];
    name[0] = 'z';
    name[1] = 'z';
    name[2] = '0' + (i / 32);
    name[3] = '0' + (i % 32);
    name[4] = '\0';
    unlink(name);
    int fd = open(name, O_CREATE|O_RDWR|O_TRUNC);
    if(fd < 0){
      // failure is eventually expected.
      break;
    }
    close(fd);
  }

  for(int i = 0; i < nzz; i++){
    char name[32];
    name[0] = 'z';
    name[1] = 'z';
    name[2] = '0' + (i / 32);
    name[3] = '0' + (i % 32);
    name[4] = '\0';
    unlink(name);
  }
}

struct test slowtests[] = {
  {bigdir, "bigdir"},
  {manywrites, "manywrites"},
  {badwrite, "badwrite" },
  {execout, "execout"},
  {diskfull, "diskfull"},
  {outofinodes, "outofinodes"},
    
  { 0, 0},
};

//
// drive tests
//

// run each test in its own process. run returns 1 if child's exit()
// indicates success.
int
run(void f(char *), char *s) {
  int pid;
  int xstatus;

  printf("test %s: ", s);
  if((pid = fork()) < 0) {
    printf("runtest: fork error\n");
    exit(1);
  }
  if(pid == 0) {
    f(s);
    exit(0);
  } else {
    wait(&xstatus);
    if(xstatus != 0) 
      printf("FAILED\n");
    else
      printf("OK\n");
    return xstatus == 0;
  }
}

int
runtests(struct test *tests, char *justone, int continuous) {
  for (struct test *t = tests; t->s != 0; t++) {
    if((justone == 0) || strcmp(t->s, justone) == 0) {
      if(!run(t->f, t->s)){
        if(continuous != 2){
          printf("SOME TESTS FAILED\n");
          return 1;
        }
      }
    }
  }
  return 0;
}


//
// use sbrk() to count how many free physical memory pages there are.
// touches the pages to force allocation.
// because out of memory with lazy allocation results in the process
// taking a fault and being killed, fork and report back.
//
int
countfree()
{
  int fds[2];

  if(pipe(fds) < 0){
    printf("pipe() failed in countfree()\n");
    exit(1);
  }
  
  int pid = fork();

  if(pid < 0){
    printf("fork failed in countfree()\n");
    exit(1);
  }

  if(pid == 0){
    close(fds[0]);
    
    while(1){
      uint64 a = (uint64) sbrk(4096);
      if(a == 0xffffffffffffffff){
        break;
      }

      // modify the memory to make sure it's really allocated.
      *(char *)(a + 4096 - 1) = 1;

      // report back one more page.
      if(write(fds[1], "x", 1) != 1){
        printf("write() failed in countfree()\n");
        exit(1);
      }
    }

    exit(0);
  }

  close(fds[1]);

  int n = 0;
  while(1){
    char c;
    int cc = read(fds[0], &c, 1);
    if(cc < 0){
      printf("read() failed in countfree()\n");
      exit(1);
    }
    if(cc == 0)
      break;
    n += 1;
  }

  close(fds[0]);
  wait((int*)0);
  
  return n;
}

int
drivetests(int quick, int continuous, char *justone) {
  do {
    printf("usertests starting\n");
    int free0 = countfree();
    int free1 = 0;
    if (runtests(quicktests, justone, continuous)) {
      if(continuous != 2) {
        return 1;
      }
    }
    if(!quick) {
      if (justone == 0)
        printf("usertests slow tests starting\n");
      if (runtests(slowtests, justone, continuous)) {
        if(continuous != 2) {
          return 1;
        }
      }
    }
    if((free1 = countfree()) < free0) {
      printf("FAILED -- lost some free pages %d (out of %d)\n", free1, free0);
      if(continuous != 2) {
        return 1;
      }
    }
  } while(continuous);
  return 0;
}

int
main(int argc, char *argv[])
{
  int continuous = 0;
  int quick = 0;
  char *justone = 0;

  if(argc == 2 && strcmp(argv[1], "-q") == 0){
    quick = 1;
  } else if(argc == 2 && strcmp(argv[1], "-c") == 0){
    continuous = 1;
  } else if(argc == 2 && strcmp(argv[1], "-C") == 0){
    continuous = 2;
  } else if(argc == 2 && argv[1][0] != '-'){
    justone = argv[1];
  } else if(argc > 1){
    printf("Usage: usertests [-c] [-C] [-q] [testname]\n");
    exit(1);
  }
  if (drivetests(quick, continuous, justone)) {
    exit(1);
  }
  printf("ALL TESTS PASSED\n");
  exit(0);
}
```
## ../user/usys.pl 
```c
#!/usr/bin/perl -w

# Generate usys.S, the stubs for syscalls.

print "# generated by usys.pl - do not edit\n";

print "#include \"kernel/syscall.h\"\n";

sub entry {
    my $name = shift;
    print ".global $name\n";
    print "${name}:\n";
    print " li a7, SYS_${name}\n";
    print " ecall\n";
    print " ret\n";
}
	
entry("fork");
entry("exit");
entry("wait");
entry("pipe");
entry("read");
entry("write");
entry("close");
entry("kill");
entry("exec");
entry("open");
entry("mknod");
entry("unlink");
entry("fstat");
entry("link");
entry("mkdir");
entry("chdir");
entry("dup");
entry("getpid");
entry("sbrk");
entry("sleep");
entry("uptime");
```
## ../user/wc.c 
```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"

char buf[512];

void
wc(int fd, char *name)
{
  int i, n;
  int l, w, c, inword;

  l = w = c = 0;
  inword = 0;
  while((n = read(fd, buf, sizeof(buf))) > 0){
    for(i=0; i<n; i++){
      c++;
      if(buf[i] == '\n')
        l++;
      if(strchr(" \r\t\n\v", buf[i]))
        inword = 0;
      else if(!inword){
        w++;
        inword = 1;
      }
    }
  }
  if(n < 0){
    printf("wc: read error\n");
    exit(1);
  }
  printf("%d %d %d %s\n", l, w, c, name);
}

int
main(int argc, char *argv[])
{
  int fd, i;

  if(argc <= 1){
    wc(0, "");
    exit(0);
  }

  for(i = 1; i < argc; i++){
    if((fd = open(argv[i], O_RDONLY)) < 0){
      printf("wc: cannot open %s\n", argv[i]);
      exit(1);
    }
    wc(fd, argv[i]);
    close(fd);
  }
  exit(0);
}
```
## ../user/zombie.c 
```c
// Create a zombie process that
// must be reparented at exit.

#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int
main(void)
{
  if(fork() > 0)
    sleep(5);  // Let child exit before parent.
  exit(0);
}
```
