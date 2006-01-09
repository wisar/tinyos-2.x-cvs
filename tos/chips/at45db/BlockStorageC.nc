// $Id$
#include "BlockStorage.h"

generic configuration BlockStorageC() {
  provides {
    interface Mount;
    interface BlockWrite;
    interface BlockRead;
  }
}
implementation {
  enum {
    BLOCK_ID = unique(UQ_BLOCK_STORAGE),
    VOLUME_ID = unique(UQ_STORAGE_VOLUME),
    RESOURCE_ID = unique(UQ_AT45DB)
  };
    
  components BlockStorageP, WireBlockStorageP, StorageManagerC, HalAt45dbC;

  Mount = BlockStorageP.Mount[BLOCK_ID];
  BlockWrite = BlockStorageP.BlockWrite[BLOCK_ID];
  BlockRead = BlockStorageP.BlockRead[BLOCK_ID];

  BlockStorageP.At45dbVolume[BLOCK_ID] -> StorageManagerC.At45dbVolume[VOLUME_ID];
  BlockStorageP.Resource[BLOCK_ID] -> HalAt45dbC.Resource[RESOURCE_ID];
}
