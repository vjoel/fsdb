// Copyright (c) 2003 Ara Howard. Ruby license, I assume?

#ifdef _WIN32
#include "missing/file.h"
#endif

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif

#include <errno.h>

extern VALUE rb_cFile;

# ifndef LOCK_SH
#  define LOCK_SH 1
# endif
# ifndef LOCK_EX
#  define LOCK_EX 2
# endif
# ifndef LOCK_NB
#  define LOCK_NB 4
# endif
# ifndef LOCK_UN
#  define LOCK_UN 8
# endif

static int
fcntl_lock (fd, operation)
     int fd;
     int operation;
{
  struct flock lock;

  switch (operation & ~LOCK_NB)
    {
    case LOCK_SH:
      lock.l_type = F_RDLCK;
      break;
    case LOCK_EX:
      lock.l_type = F_WRLCK;
      break;
    case LOCK_UN:
      lock.l_type = F_UNLCK;
      break;
    default:
      errno = EINVAL;
      return -1;
    }
  lock.l_whence = SEEK_SET;
  lock.l_start = lock.l_len = 0L;
  return fcntl (fd, (operation & LOCK_NB) ? F_SETLK : F_SETLKW, &lock);
}


static VALUE
rb_file_fcntl_lock (obj, operation)
     VALUE obj;
     VALUE operation;
{
#ifndef __CHECKER__
  OpenFile *fptr;
  int ret;

  rb_secure (2);
  GetOpenFile (obj, fptr);

  if (fptr->mode & FMODE_WRITABLE)
    {
      fflush (GetWriteFile (fptr));
    }
retry:
  TRAP_BEG;
  ret = fcntl_lock (fileno (fptr->f), NUM2INT (operation));
  TRAP_END;
  if (ret < 0)
    {
      switch (errno)
	{
	case EAGAIN:
	case EACCES:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	case EWOULDBLOCK:
#endif
	  return Qfalse;
	case EINTR:
#if defined(ERESTART)
	case ERESTART:
#endif
	  goto retry;
	}
      rb_sys_fail (fptr->path);
    }
#endif

  return INT2FIX (0);
}


void
Init_fcntl_lock()
{
    rb_define_method(rb_cFile, "fcntl_lock", rb_file_fcntl_lock, 1);
}
