/*									tab:4
 * "Copyright (c) 2000-2004 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Copyright (c) 2002-2006 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/**
 * Private component of the AT45DB implementation of the log storage
 * abstraction.
 *
 * @author: David Gay <dgay@acm.org>
 * @author: Jonathan Hui <jwhui@cs.berkeley.edu>
 */

#include <Storage.h>
#include <crc.h>

module LogStorageP {
  provides {
    interface LogWrite as LinearWrite[logstorage_t logId];
    interface LogRead as LinearRead[logstorage_t logId];
    interface LogWrite as CircularWrite[logstorage_t logId];
    interface LogRead as CircularRead[logstorage_t logId];
  }
  uses {
    interface At45db;
    interface At45dbVolume[logstorage_t logId];
    interface Resource[logstorage_t logId];
  }
}
implementation
{
  enum {
    F_SYNC = 1,
    F_CIRCLED = 2,
    F_LASTVALID = 4
  };

  nx_struct pageinfo {
    nx_uint16_t magic;
    nx_uint32_t pos;
    nx_uint8_t lastRecordOffset;
    nx_uint8_t flags;
    nx_uint16_t crc;
  };

  enum {
    N = uniqueCount(UQ_LOG_STORAGE),
    NO_CLIENT = 0xff,
    PAGE_SIZE = AT45_PAGE_SIZE - sizeof(nx_struct pageinfo),
    PERSISTENT_MAGIC = 0x4256,
  };

  enum {
    R_IDLE,
    R_ERASE,
    R_APPEND,
    R_SYNC,
    R_READ,
    R_SEEK
  };

  enum {
    META_IDLE,
    META_LOCATE,
    META_LOCATELAST,
    META_SEEK,
    META_READ,
    META_WRITE
  };

  uint8_t client = NO_CLIENT;
  uint8_t metaState;
  at45page_t firstPage, lastPage;
  storage_len_t len;
  nx_struct pageinfo metadata;

  struct {
    /* The latest request made for this client, and it's arguments */
    uint8_t request; 
    uint8_t *buf;
    storage_len_t len;

    /* Log r/w positions */
    bool positionKnown : 1;
    bool circular : 1;
    bool circled : 1;
    bool rvalid : 1;
    uint32_t wpos;		/* Bytes since start of logging */
    at45page_t wpage;		/* Current write page */
    at45pageoffset_t woffset;	/* Offset on current write page */
    uint32_t rpos;		/* Bytes since start of logging */
    at45page_t rpage;		/* Current read page */
    at45pageoffset_t roffset;	/* Offset on current read page */
    at45pageoffset_t rend;	/* Last valid offset on current read page */
  } s[N];

  at45page_t firstVolumePage() {
    return call At45dbVolume.remap[client](0);
  }

  at45page_t lastVolumePage() {
    return call At45dbVolume.remap[client](call At45dbVolume.volumeSize[client]() >> AT45_PAGE_SIZE_LOG2);
  }

  void setWritePage(at45page_t page) {
    if (s[client].circular && page == lastVolumePage())
      {
	s[client].circled = TRUE;
	page = firstVolumePage();
      }
    s[client].wpage = page;
    s[client].woffset = 0;
  }

  void readFromBeginning() {
    /* Set position to end of previous page, to force page advance
       on next read */
    s[client].rpos = 0;
    s[client].rpage = firstVolumePage() - 1;
    s[client].rend = s[client].roffset = 0;
    s[client].rvalid = TRUE;
  }

  void invalidateReadPointer() {
    s[client].rvalid = FALSE;
  }

  void crcPage(at45page_t page) {
    call At45db.computeCrc(page, 0,
			   PAGE_SIZE + offsetof(nx_struct pageinfo, crc), 0);
  }

  void readMetadata(at45page_t page) {
    call At45db.read(page, PAGE_SIZE, &metadata, sizeof metadata);
  }

  void writeMetadata(at45page_t page) {
    call At45db.write(page, PAGE_SIZE, &metadata, sizeof metadata);
  }

  void emptyLog() {
    s[client].positionKnown = TRUE;
    s[client].wpos = 0;
    setWritePage(firstVolumePage()); 
    readFromBeginning();
  }

  /* ------------------------------------------------------------------ */
  /* Queue and initiate user requests					*/
  /* ------------------------------------------------------------------ */

  void eraseStart();
  void appendStart();
  void syncStart();
  void readStart();
  void locateStart();
  void rmetadataStart();
  void wmetadataStart();
  void seekStart();

  void startRequest() {
    if (!s[client].positionKnown && s[client].request != R_ERASE)
      {
	locateStart();
	return;
      }

    metaState = META_IDLE;
    switch (s[client].request)
      {
      case R_ERASE: eraseStart(); break;
      case R_APPEND: appendStart(); break;
      case R_SYNC: syncStart(); break;
      case R_READ: readStart(); break;
      case R_SEEK: seekStart(); break;
      }
  }

  void endRequest(error_t ok) {
    logstorage_t c = client;
    uint8_t request = s[c].request;
    storage_len_t actualLen = s[c].len - len;
    void *ptr = s[c].buf - actualLen;
    
    client = NO_CLIENT;
    s[c].request = R_IDLE;
    call Resource.release[c]();

    if (s[c].circular)
      switch (request)
	{
	case R_ERASE: signal CircularWrite.eraseDone[c](ok); break;
	case R_APPEND: signal CircularWrite.appendDone[c](ptr, actualLen, ok); break;
	case R_SYNC: signal CircularWrite.syncDone[c](ok); break;
	case R_READ: signal CircularRead.readDone[c](ptr, actualLen, ok); break;
	}
    else
      switch (request)
	{
	case R_ERASE: signal LinearWrite.eraseDone[c](ok); break;
	case R_APPEND: signal LinearWrite.appendDone[c](ptr, actualLen, ok); break;
	case R_SYNC: signal LinearWrite.syncDone[c](ok); break;
	case R_READ: signal LinearRead.readDone[c](ptr, actualLen, ok); break;
	}
  }

  error_t newRequest(uint8_t newRequest, logstorage_t id, bool circular,
		     uint8_t *buf, storage_len_t length) {
    if (s[id].request != R_IDLE)
      return FAIL;

    /* You can make the transition from linear->circular once. */
    if (s[id].circular && !circular)
      return FAIL;
    s[id].circular = circular;

    s[id].request = newRequest;
    s[id].buf = buf;
    s[id].len = length;
    call Resource.request[id]();

    return SUCCESS;
  }

  event void Resource.granted[logstorage_t id]() {
    client = id;
    len = s[client].len;
    startRequest();
  }

  command error_t LinearWrite.append[logstorage_t id](void* buf, storage_len_t length) {
    return newRequest(R_APPEND, id, FALSE, buf, length);
  }

  command uint32_t LinearWrite.currentOffset[logstorage_t id]() {
   return s[id].wpos;
  }

  command error_t LinearWrite.erase[logstorage_t id]() {
    return newRequest(R_ERASE, id, FALSE, NULL, 0);
  }

  command error_t LinearWrite.sync[logstorage_t id]() {
    return newRequest(R_SYNC, id, FALSE, NULL, 0);
  }

  command error_t LinearRead.read[logstorage_t id](void* buf, storage_len_t length) {
    return newRequest(R_READ, id, FALSE, buf, length);
  }

  command uint32_t LinearRead.currentOffset[logstorage_t id]() {
    return s[id].rpos;
  }

  command error_t LinearRead.seek[logstorage_t id](uint32_t offset) {
    return newRequest(R_SEEK, id, FALSE, (void *)(offset >> 16), offset);
  }

  command error_t CircularWrite.append[logstorage_t id](void* buf, storage_len_t length) {
    return newRequest(R_APPEND, id, TRUE, buf, length);
  }

  command uint32_t CircularWrite.currentOffset[logstorage_t id]() {
    return s[id].wpos;
  }

  command error_t CircularWrite.erase[logstorage_t id]() {
    return newRequest(R_ERASE, id, TRUE, NULL, 0);
  }

  command error_t CircularWrite.sync[logstorage_t id]() {
    return newRequest(R_SYNC, id, TRUE, NULL, 0);
  }

  command error_t CircularRead.read[logstorage_t id](void* buf, storage_len_t length) {
    return newRequest(R_READ, id, TRUE, buf, length);
  }

  command uint32_t CircularRead.currentOffset[logstorage_t id]() {
    return s[id].rpos;
  }

  command error_t CircularRead.seek[logstorage_t id](uint32_t offset) {
    return newRequest(R_SEEK, id, TRUE, (void *)(offset >> 16), offset);
  }
  /* ------------------------------------------------------------------ */
  /* Erase								*/
  /* ------------------------------------------------------------------ */

  void eraseContinue() {
    /* We erase backwards. That leaves the first two pages in the cache */
    if (lastPage == firstPage)
      {
	emptyLog();
	endRequest(SUCCESS);
      }
    else
      call At45db.erase(--lastPage, AT45_ERASE);
  }

  void eraseStart() {
    firstPage = firstVolumePage();
    lastPage = lastVolumePage();
    eraseContinue();
  }

  /* ------------------------------------------------------------------ */
  /* Locate log boundaries						*/
  /* ------------------------------------------------------------------ */

  at45page_t locateCurrentPage() {
    return firstPage + ((lastPage - firstPage + 1) >> 1);
  }

  void locateLastRecord() {
    if (firstPage == firstVolumePage())
      {
	/* Nothing valid found. We're done (log is empty). */
	emptyLog();
	startRequest();
      }
    else
      readMetadata(--firstPage);
  }

  void locateLastReadDone() {
    if (metadata.magic == PERSISTENT_MAGIC && metadata.flags & F_LASTVALID)
      crcPage(firstPage);
    else
      locateLastRecord();
  }

  void locateLastCrcDone(uint16_t crc) {
    if (crc == metadata.crc)
      {
	/* We've found the last valid page with a record-end */
	s[client].positionKnown = TRUE;
	if (metadata.flags & F_SYNC) /* must start on next page */
	  setWritePage(firstPage + 1);
	else
	  {
	    s[client].wpage = firstPage;
	    s[client].woffset = metadata.lastRecordOffset;
	  }
	s[client].wpos = metadata.pos + metadata.lastRecordOffset;

	/* If we're on the first pass (no F_CIRCLED flag), the read
	   pointer starts at the beginning of the flash. Otherwise,
	   we invalidate it, which will force read requests to find
	   the first valid page after the current write pointer. */
	s[client].circled = (metadata.flags & F_CIRCLED) != 0;
	if (s[client].circled)
	  {
	    if (!s[client].circular) // oops
	      {
		/* Maybe treating the log as empty would be better? */
		endRequest(FAIL);
		return;
	      }

	    invalidateReadPointer();
	  }
	else
	  readFromBeginning();

	startRequest();
      }
    else
      locateLastRecord();
  }

  void located() {
    metaState = META_LOCATELAST;
    /* firstPage is one after last valid page, but the last page with
       a record end may be some pages earlier. Search for it. */
    locateLastRecord();
  }

  void locateBinarySearch() {
    if ((int)lastPage - (int)firstPage < 0)
      located();
    else
      readMetadata(locateCurrentPage());
  }

  void locateGreaterThan() {
    firstPage = locateCurrentPage() + 1;
    locateBinarySearch();
  }

  void locateLessThan() {
    lastPage = locateCurrentPage() - 1;
    locateBinarySearch();
  }

  void locateReadDone() {
    if (metadata.magic == PERSISTENT_MAGIC && s[client].wpos < metadata.pos)
      crcPage(locateCurrentPage());
    else
      locateLessThan();
  }

  void locateCrcDone(uint16_t crc) {
    if (crc == metadata.crc)
      {
	s[client].wpos = metadata.pos + 1;
	locateGreaterThan();
      }
    else
      locateLessThan();
  }

  /* Locate log beginning and ending */
  void locateStart() {
    metaState = META_LOCATE;
    firstPage = firstVolumePage();
    lastPage = lastVolumePage() - 1;
    /* We track the page with the largest position found. We store
       largest-offset-found+1, so that we can use 0 as a value smaller
       than all valid positions. Note that wpos is set correctly once
       we find the actual last page. */
    s[client].wpos = 0;
    locateBinarySearch();
  }

  /* ------------------------------------------------------------------ */
  /* Append								*/
  /* ------------------------------------------------------------------ */

  void appendContinue() {
    uint8_t *buf = s[client].buf;
    at45pageoffset_t offset = s[client].woffset, count;
    
    if (len == 0)
      {
	endRequest(SUCCESS);
	return;
      }

    if (s[client].wpage == lastVolumePage())
      {
	endRequest(ESIZE);
	return;
      }

    if (offset + len <= PAGE_SIZE)
      count = len;
    else
      count = PAGE_SIZE - offset;

    s[client].buf += count;
    s[client].wpos += count;
    s[client].woffset += count;
    len -= count;

    call At45db.write(s[client].wpage, offset, buf, count);
  }
  
  void appendWriteDone() {
    if (s[client].woffset == PAGE_SIZE) /* Time to write metadata */
      wmetadataStart();
    else
      endRequest(SUCCESS);
  }

  void appendMetadataDone(error_t ok) { // metadata of previous page flushed
    if (ok != SUCCESS)
      endRequest(FAIL);
    else
      {
	/* Setup metadata in case we overflow this page too */
	metadata.flags = 0;
	appendContinue();
      }
  }

  void appendStart() {
    /* Set lastRecordOffset in case we need to write metadata (see
       wmetadataStart) */
    metadata.lastRecordOffset = s[client].woffset;
    metadata.flags = F_LASTVALID;
    appendContinue();
  }

  /* ------------------------------------------------------------------ */
  /* Sync								*/
  /* ------------------------------------------------------------------ */

  void syncStart() {
    if (s[client].woffset == 0) /* we can't lose any writes */
      endRequest(SUCCESS);
    else
      {
	metadata.flags = F_SYNC | F_LASTVALID;
	metadata.lastRecordOffset = s[client].woffset;
	wmetadataStart();
      }
  }

  void syncMetadataDone(error_t ok) {
    endRequest(ok);
  }

  /* ------------------------------------------------------------------ */
  /* Write block metadata						*/
  /* ------------------------------------------------------------------ */

  void wmetadataStart() {
    /* The caller ensures that metadata is set correctly. */
    metaState = META_WRITE;
    firstPage = s[client].wpage; // remember page to commit
    metadata.pos = s[client].wpos - s[client].woffset;
    call At45db.computeCrc(firstPage, 0, PAGE_SIZE, 0);

    /* We move to the next page now. If writing the metadata fails, we'll
       simply leave the invalid page in place. Trying to recover seems
       complicated, and of little benefit (note that in practice, At45dbC
       shuts down after a failed write, so nothing is really going to
       happen after that anyway). */
    setWritePage(s[client].wpage + 1);

    /* Invalidate read pointer if we reach it's page */
    if (s[client].wpage == s[client].rpage)
      invalidateReadPointer();
  }

  void wmetadataCrcDone(uint16_t crc) {
    uint8_t i, *md;

    metadata.magic = PERSISTENT_MAGIC;
    if (s[client].circled)
      metadata.flags |= F_CIRCLED;

    // Include metadata in crc
    md = (uint8_t *)&metadata;
    for (i = 0; i < offsetof(nx_struct pageinfo, crc); i++)
      crc = crcByte(crc, md[i]);
    metadata.crc = crc;

    // And save it
    writeMetadata(firstPage);
  }

  void wmetadataWriteDone() {
    metaState = META_IDLE;
    if (s[client].request == R_SYNC)
      call At45db.sync(firstPage);
    else
      call At45db.flush(firstPage);
  }

  /* ------------------------------------------------------------------ */
  /* Read 								*/
  /* ------------------------------------------------------------------ */

  void readContinue() {
    uint8_t *buf = s[client].buf;
    at45pageoffset_t offset = s[client].roffset, count;
    at45pageoffset_t end = s[client].rend;
    
    if (len == 0)
      {
	endRequest(SUCCESS);
	return;
      }

    if (!s[client].rvalid)
      {
	/* Find a valid page after wpage */
	s[client].rpage = s[client].wpage;
	rmetadataStart();
	return;
      }

    if (s[client].rpage == s[client].wpage)
      end = s[client].woffset;

    if (offset == end)
      {
	if ((s[client].rpage + 1 == lastVolumePage() && !s[client].circular) ||
	    s[client].rpage == s[client].wpage)
	  endRequest(ESIZE);
	else
	  rmetadataStart();
	return;
      }

    if (offset + len <= end)
      count = len;
    else
      count = end - offset;

    s[client].buf += count;
    len -= count;
    s[client].rpos += count;
    s[client].roffset = offset + count;

    call At45db.read(s[client].rpage, offset, buf, count);
  }

  void readStart() {
    readContinue();
  }

  /* ------------------------------------------------------------------ */
  /* Read block metadata						*/
  /* ------------------------------------------------------------------ */

  void continueReadAt(at45pageoffset_t roffset) {
    metaState = META_IDLE;
    s[client].rpos = metadata.pos + roffset;
    s[client].rpage = firstPage;
    s[client].roffset = roffset;
    s[client].rend =
      metadata.flags & F_SYNC ? metadata.lastRecordOffset : PAGE_SIZE;
    s[client].rvalid = TRUE;
    readContinue();
  }

  void rmetadataContinue() {
    if (++firstPage == lastVolumePage())
      firstPage = firstVolumePage();
    if (firstPage == s[client].wpage)
      {
	if (!s[client].rvalid)
	  /* We cannot find a record boundary to start at (we've just
	     walked through the whole log...). Give up. */
	  endRequest(ESIZE);
	else
	  {
	    /* The current write page has no metadata yet, so we fake it */
	    metadata.flags = 0;
	    metadata.pos = s[client].wpos - s[client].woffset;
	    continueReadAt(0);
	  }
      }
    else
      readMetadata(firstPage);
  }

  void rmetadataReadDone() {
    if (metadata.magic == PERSISTENT_MAGIC)
      crcPage(firstPage);
    else
      endRequest(ESIZE);
  }

  void rmetadataCrcDone(uint16_t crc) {
    if (!s[client].rvalid)
      if (crc == metadata.crc && metadata.flags & F_LASTVALID)
	continueReadAt(metadata.lastRecordOffset);
      else
	rmetadataContinue();
    else 
      if (crc == metadata.crc)
	continueReadAt(0);
      else
	endRequest(ESIZE);
  }

  void rmetadataStart() {
    metaState = META_READ;
    firstPage = s[client].rpage;
    rmetadataContinue();
  }

  /* ------------------------------------------------------------------ */
  /* Seek. UNTESTED, PROBABLY DOESN'T WORK.				*/
  /* ------------------------------------------------------------------ */

  at45page_t seekCurrentPage() {
    return firstPage + ((lastPage - firstPage + 1) >> 1);
  }

  at45page_t seekRealPage(at45page_t cpage) {
    if (s[client].circled)
      {
	cpage += s[client].wpage + 1;
	if (cpage >= lastVolumePage())
	  cpage -= lastVolumePage() - firstVolumePage();

	return cpage;
      }
    else
      return firstVolumePage() + cpage;
  }

  void seekBinarySearch() {
    if ((int)lastPage - (int)firstPage < 0)
      {
	/* It must be before the beginning, so we must be in the circled
	   case. Leave it up to the next read. */
	invalidateReadPointer();
	endRequest(SUCCESS);
      }
    else
      readMetadata(seekRealPage(seekCurrentPage()));
  }

  void seekReadDone() {
    crcPage(seekRealPage(seekCurrentPage()));
  }

  void seekCrcDone(uint16_t crc) {
    at45page_t cpage = seekCurrentPage();

    if (metadata.magic == PERSISTENT_MAGIC && crc == metadata.crc)
      {
	uint32_t pageStart = metadata.pos, pageEnd;

	if (metadata.flags & F_SYNC)
	  pageEnd = pageStart + metadata.lastRecordOffset;
	else
	  pageEnd = pageStart + PAGE_SIZE;
	if (s[client].rpos >= pageStart)
	  {
	    if (s[client].rpos < pageEnd)
	      {
		s[client].rpage = seekRealPage(seekCurrentPage());
		s[client].roffset = s[client].rpos - pageStart;
		s[client].rend = 
		  metadata.flags & F_SYNC ? metadata.lastRecordOffset : PAGE_SIZE;
		endRequest(SUCCESS);
		return;
	      }
	    firstPage = cpage + 1;
	  }
	else
	  lastPage = cpage - 1;
	seekBinarySearch();
      }
    else
      /* The first page after wpage may be invalid (from an earlier
	 failure). Seeks that have searched all the way to there indicate
	 a seek before the beginning of the log. 
	 All other failures indicate a corrupted page in the log, in
	 which case we fail the seek */
      if (cpage == 0)
	{
	  invalidateReadPointer();
	  endRequest(SUCCESS);
	}
      else
	endRequest(FAIL);
  }

  /* Locate a specific offset. */
  void seekStart() {
    uint32_t offset = (uint32_t)(uint16_t)s[client].buf << 16 | s[client].len;

    if (offset > s[client].wpos)
      offset = s[client].wpos; // don't go beyond end

    s[client].rpos = offset;
    s[client].rvalid = TRUE;

    // The last page's metadata isn't written to flash yet. Special case it.
    if (offset >= s[client].wpos - s[client].woffset)
      {
	s[client].rpage = s[client].wpage;
	s[client].roffset = offset - (s[client].wpos - s[client].woffset);
	s[client].rend = PAGE_SIZE;
	endRequest(SUCCESS);
      }
    else
      {
	metaState = META_SEEK;

	/* Page numbers are relative to the beginning of the log, which is
	   firstVolumePage() when the log hasn't circled, and wpage+1 when
	   it has */
	firstPage = 0;
	if (s[client].circled)
	  lastPage = (call At45dbVolume.volumeSize[client]() >> AT45_PAGE_SIZE_LOG2) - 2;
	else
	  lastPage = s[client].wpage - firstVolumePage() - 1;

	seekBinarySearch();
      }
  }

  /* ------------------------------------------------------------------ */
  /* Dispatch HAL operations to current user op				*/
  /* ------------------------------------------------------------------ */

  event void At45db.eraseDone(error_t error) {
    if (client != NO_CLIENT)
      if (error != SUCCESS)
	endRequest(error);
      else
	eraseContinue();
  }

  event void At45db.writeDone(error_t error) {
    if (client != NO_CLIENT)
      if (error != SUCCESS)
	endRequest(error);
      else
	switch (metaState)
	  {
	  case META_WRITE: wmetadataWriteDone(); break;
	  case META_IDLE: appendWriteDone(); break;
	  }
  }

  event void At45db.syncDone(error_t error) {
    if (client != NO_CLIENT)
      syncMetadataDone(error);
  }

  event void At45db.flushDone(error_t error) {
    if (client != NO_CLIENT)
      appendMetadataDone(error);
  }

  event void At45db.readDone(error_t error) {
    if (client != NO_CLIENT)
      if (error != SUCCESS)
	endRequest(error);
      else
	switch (metaState)
	  {
	  case META_LOCATE: locateReadDone(); break;
	  case META_LOCATELAST: locateLastReadDone(); break;
	  case META_SEEK: seekReadDone(); break;
	  case META_READ: rmetadataReadDone(); break;
	  case META_IDLE: readContinue(); break;
	  }					    
  }

  event void At45db.computeCrcDone(error_t error, uint16_t crc) {
    if (client != NO_CLIENT)
      if (error != SUCCESS)
	endRequest(error);
      else
	switch (metaState)
	  {
	  case META_LOCATE: locateCrcDone(crc); break;
	  case META_LOCATELAST: locateLastCrcDone(crc); break;
	  case META_SEEK: seekCrcDone(crc); break;
	  case META_WRITE: wmetadataCrcDone(crc); break;
	  case META_READ: rmetadataCrcDone(crc); break;
	  }
  }

  default event void LinearWrite.appendDone[logstorage_t logId](void* buf, storage_len_t l, error_t error) { }
  default event void LinearWrite.eraseDone[logstorage_t logId](error_t error) { }
  default event void LinearWrite.syncDone[logstorage_t logId](error_t error) { }
  default event void LinearRead.readDone[logstorage_t logId](void* buf, storage_len_t l, error_t error) { }
  default event void LinearRead.seekDone[logstorage_t logId](error_t error) {}

  default event void CircularWrite.appendDone[logstorage_t logId](void* buf, storage_len_t l, error_t error) { }
  default event void CircularWrite.eraseDone[logstorage_t logId](error_t error) { }
  default event void CircularWrite.syncDone[logstorage_t logId](error_t error) { }
  default event void CircularRead.readDone[logstorage_t logId](void* buf, storage_len_t l, error_t error) { }
  default event void CircularRead.seekDone[logstorage_t logId](error_t error) {}

  default command at45page_t At45dbVolume.remap[logstorage_t logId](at45page_t volumePage) {return 0;}
  default command storage_len_t At45dbVolume.volumeSize[logstorage_t logId]() {return 0;}
  default async command error_t Resource.request[logstorage_t logId]() {return SUCCESS;}
  default async command void Resource.release[logstorage_t logId]() { }

}