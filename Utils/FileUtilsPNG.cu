// Copyright 2014-2015 Isis Innovation Limited and the authors of InfiniTAM

#include "FileUtils.h"

#include <stdio.h>
#include <fstream>
using namespace std;

#include "..\png\lodepng.h"

namespace png {
    void SaveImageToFile(const ITMUChar4Image* image, const char* fileName, bool flipVertical)
    {
        unsigned char *data = new unsigned char[image->noDims.x*image->noDims.y * 3];

        Vector2i noDims = image->noDims;

        if (flipVertical)
        {
            for (int y = 0; y < noDims.y; y++) for (int x = 0; x < noDims.x; x++)
            {
                int locId_src, locId_dst;
                locId_src = x + y * noDims.x;
                locId_dst = x + (noDims.y - y - 1) * noDims.x;

                data[locId_dst * 3 + 0] = image->GetData(MEMORYDEVICE_CPU)[locId_src].x;
                data[locId_dst * 3 + 1] = image->GetData(MEMORYDEVICE_CPU)[locId_src].y;
                data[locId_dst * 3 + 2] = image->GetData(MEMORYDEVICE_CPU)[locId_src].z;
            }
        }
        else
        {
            for (int i = 0; i < noDims.x * noDims.y; ++i) {
                data[i * 3 + 0] = image->GetData(MEMORYDEVICE_CPU)[i].x;
                data[i * 3 + 1] = image->GetData(MEMORYDEVICE_CPU)[i].y;
                data[i * 3 + 2] = image->GetData(MEMORYDEVICE_CPU)[i].z;
            }
        }

        lodepng_encode24_file(fileName, data, noDims.x, noDims.y);

        delete[] data;
    }

    void SaveImageToFile(const ITMShortImage* image, const char* fileName)
    {
        short *data = (short*)malloc(sizeof(short) * image->dataSize);
        const short *dataSource = image->GetData(MEMORYDEVICE_CPU);
        for (size_t i = 0; i < image->dataSize; i++) data[i] = (dataSource[i] << 8) | ((dataSource[i] >> 8) & 255);


        lodepng_encode_file(fileName, (unsigned char*)data, image->noDims.x, image->noDims.y, LCT_GREY, 16);

        delete data;
    }

    void SaveImageToFile(const ITMFloatImage* image, const char* fileName)
    {
        unsigned short *data = new unsigned short[image->dataSize];
        for (size_t i = 0; i < image->dataSize; i++)
        {
            float localData = image->GetData(MEMORYDEVICE_CPU)[i];
            data[i] = localData >= 0 ? (unsigned short)(localData * 1000.0f) : 0;
        }


        lodepng_encode_file(fileName, (unsigned char*)data, image->noDims.x, image->noDims.y, LCT_GREY, 16);

        delete[] data;
    }

    bool ReadImageFromFile(ITMUChar4Image* image, const char* fileName)
    {
        unsigned int xsize, ysize;
        unsigned char* data;
        lodepng_decode24_file(&data, &xsize, &ysize, fileName);

        Vector2i newSize(xsize, ysize);
        image->ChangeDims(newSize);
        Vector4u *dataPtr = image->GetData(MEMORYDEVICE_CPU);

        for (int i = 0; i < image->noDims.x*image->noDims.y; ++i)
        {
            dataPtr[i].x = data[i * 3 + 0]; dataPtr[i].y = data[i * 3 + 1];
            dataPtr[i].z = data[i * 3 + 2]; dataPtr[i].w = 255;
        }
        free(data);

        return true;
    }

    bool ReadImageFromFile(ITMShortImage *image, const char *fileName)
    {
        unsigned int xsize, ysize;
        short* data;
        lodepng_decode_file((unsigned char**)&data, &xsize, &ysize, fileName, LCT_GREY, 16);


        Vector2i newSize(xsize, ysize);
        image->ChangeDims(newSize);

        memcpy(image->GetData(MEMORYDEVICE_CPU),
            data,
            image->noDims.x*image->noDims.y * sizeof(short));

        free(data);

        return true;
    }

}