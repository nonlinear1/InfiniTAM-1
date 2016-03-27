#include "Scene.h"

//__device__ Scene* currentScene;
//__host__
__managed__ Scene* currentScene = 0; // TODO use __const__ memory, not changeable from gpu!

CPU_AND_GPU Scene* Scene::getCurrentScene() {
    return currentScene;
}

__managed__ ITMVoxelBlock* currentLocalVBA = 0;
__device__ void Scene::AllocateVB::allocate(VoxelBlockPos pos, int sequenceId) {
    assert(currentLocalVBA);

    // Initialize pos and reset data
    currentLocalVBA[sequenceId].pos = pos;
    currentLocalVBA[sequenceId].resetVoxels();
}

void Scene::setCurrentScene(Scene* s) {
    cudaDeviceSynchronize(); // want to write managed currentScene 
    currentScene = s;
}

Scene::Scene() {
    voxelBlockHash = new HashMap<Z3Hasher, AllocateVB>(SDF_EXCESS_LIST_SIZE);
    cudaSafeCall(cudaMalloc(&localVBA, sizeof(ITMVoxelBlock) *SDF_LOCAL_BLOCK_NUM));
}

Scene::~Scene() {
    delete voxelBlockHash;
    cudaFree(localVBA);
}

void Scene::performAllocations() {
    currentLocalVBA = localVBA;
    voxelBlockHash->performAllocations();
}

static GPU_ONLY inline void pointToVoxelBlockPos(
    const THREADPTR(Vector3i) & point, //!< [in] in voxel coordinates
    THREADPTR(VoxelBlockPos) &blockPos, //!< [out] In voxel-block coordinates, floor(voxel coordinate / SDF_BLOCK_SIZE)
    THREADPTR(int) &voxelLocalId //!< [out] index into the found voxel block to find the voxel
    ) {
    // "The 3D voxel block location is obtained by dividing the voxel coordinates with the block size along each axis."

    // if SDF_BLOCK_SIZE == 8, then -3 should go to block -1, so we need to adjust negative values 
    // (C's quotient-remainder division gives -3/8 == 0)
    blockPos.x = ((point.x < 0) ? point.x - SDF_BLOCK_SIZE + 1 : point.x) / SDF_BLOCK_SIZE;
    blockPos.y = ((point.y < 0) ? point.y - SDF_BLOCK_SIZE + 1 : point.y) / SDF_BLOCK_SIZE;
    blockPos.z = ((point.z < 0) ? point.z - SDF_BLOCK_SIZE + 1 : point.z) / SDF_BLOCK_SIZE;

    Vector3i locPos = point - blockPos.toInt() * SDF_BLOCK_SIZE; // localized coordinate
    voxelLocalId = locPos.x + locPos.y * SDF_BLOCK_SIZE + locPos.z * SDF_BLOCK_SIZE * SDF_BLOCK_SIZE;
}

GPU_ONLY ITMVoxel* Scene::getVoxel(Vector3i pos) {
    VoxelBlockPos blockPos;
    int voxelLocalId;
    pointToVoxelBlockPos(pos, blockPos, voxelLocalId);

    ITMVoxelBlock* b = getVoxelBlock(blockPos);
    if (b == NULL) return NULL;
    return &b->blockVoxels[voxelLocalId];
}

/// Returns NULL if the voxel block is not allocated
GPU_ONLY ITMVoxelBlock* Scene::getVoxelBlock(VoxelBlockPos pos) {
    int sequenceNumber = voxelBlockHash->getSequenceNumber(pos);
    if (sequenceNumber == 0) return NULL;
    return &localVBA[sequenceNumber];
}

GPU_ONLY void Scene::requestVoxelBlockAllocation(VoxelBlockPos pos) {
    voxelBlockHash->requestAllocation(pos);
}
