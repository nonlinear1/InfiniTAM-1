// Copyright 2014-2015 Isis Innovation Limited and the authors of InfiniTAM

#pragma once


#ifndef COMPILE_WITHOUT_CUDA
#include "..\Engine\DeviceSpecific\CUDA\ITMCUDAUtils.h"
#else 
struct Managed {};
#define __device__
#endif

#include <stdlib.h>

#include "../Utils/ITMLibDefines.h"
#include "../../ORUtils/MemoryBlock.h"

namespace ITMLib
{
	namespace Objects
	{
		/** \brief
		Stores the actual voxel content that is referred to by a
		ITMLib::Objects::ITMHashTable.
		*/
		template<class TVoxel>
		class ITMLocalVBA
		{
		private:
			ORUtils::MemoryBlock<TVoxel> *voxelBlocks;

            const MemoryDeviceType memoryType;

		public:
			inline TVoxel *GetVoxelBlocks(void) { return voxelBlocks->GetData(memoryType); }
			inline const TVoxel *GetVoxelBlocks(void) const { return voxelBlocks->GetData(memoryType); }

			const int allocatedSize;

            /// Allocation list generating sequential ids
            // Implemented as a countdown semaphore in CUDA unified memory
            // Filled from the top
            class VoxelAllocationList : public Managed {
            private:
                /// This index is considered free in the list
                int lastFreeEntry;
                const int capacity;
                ORUtils::MemoryBlock<int> _allocationList;
                int* allocationList;

            public:
                VoxelAllocationList(int capacity, MemoryDeviceType memoryType) : 
                    capacity(capacity), _allocationList(capacity, memoryType) {
                    allocationList = _allocationList.GetData(memoryType);
                    Reset();
                }

                /// Returns a free ptr in the local voxel block array
                /// to be used as the .ptr attribut
                // Assume single threaded
                // TODO return 0 when nothing can be allocated (full)
                __device__ int Allocate() {
                    int ptr;
#if !defined(COMPILE_WITHOUT_CUDA) && defined(__CUDACC__)
                    // Must atomically decrease lastFreeEntry, but retrieve the value at the previous
                    int newlyReservedEntry = atomicSub(&lastFreeEntry, 1);
#else
                    int newlyReservedEntry = lastFreeEntry--;
#endif
                    ptr = allocationList[newlyReservedEntry];
                    allocationList[newlyReservedEntry] = -1; // now illegal - updating this is not strictly necessary

                    return ptr;
                }

                __device__ void Free(int ptr) {
                    // TODO dont accept when list is full already or when this was never allocated
                    // that is, when lastFreeEntry >= SDF_LOCAL_BLOCK_NUM - 1
                    // ^^ should never happen

#if !defined(COMPILE_WITHOUT_CUDA) && defined(__CUDACC__)
                    int newlyFreedEntry = atomicAdd(&lastFreeEntry, 1) + 1; // atomicAdd returns the last value, but the new value
                    // is what is newly free. We should not read the changed lastFreeEntry as it might have changed yet again!
#else
                    int newlyFreedEntry = lastFreeEntry++;
#endif
                    allocationList[newlyFreedEntry] = ptr;
                }

                void Reset() {
                    lastFreeEntry = capacity - 1;

                    // allocationList initially contains [0:capacity-1]
#if !defined(COMPILE_WITHOUT_CUDA) && defined(__CUDACC__)
                    fillArrayKernel<int>(allocationList, capacity);
#else
                    for (int i = 0; i < capacity; ++i) allocationList[i] = i;
#endif
                }
            } *voxelAllocationList;


            ITMLocalVBA(MemoryDeviceType memoryType, int noBlocks, int blockSize) :
                memoryType(memoryType),
                allocatedSize(noBlocks * blockSize)
			{
				voxelBlocks = new ORUtils::MemoryBlock<TVoxel>(allocatedSize, memoryType);
                voxelAllocationList = new VoxelAllocationList(noBlocks, memoryType);
			}

			~ITMLocalVBA(void)
			{
				delete voxelBlocks;
                delete voxelAllocationList;
			}

			// Suppress the default copy constructor and assignment operator
			ITMLocalVBA(const ITMLocalVBA&);
			ITMLocalVBA& operator=(const ITMLocalVBA&);
		};
	}
}
