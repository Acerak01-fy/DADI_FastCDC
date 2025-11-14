/*
   Copyright The Overlaybd Authors

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

#include "fastcdc_wrapper.h"
#include <photon/common/alog.h>
#include <climits>

// Include FastCDC C library
extern "C" {
#include "../../../FastCDC-c/fastcdc.h"
}

namespace ZFile {

// Static initialization flag
bool FastCDCChunker::s_initialized = false;

FastCDCChunker::FastCDCChunker(uint32_t min_size, uint32_t avg_size, uint32_t max_size)
    : m_min_size(min_size), m_avg_size(avg_size), m_max_size(max_size) {
    
    // Initialize the Gear hash table (only once globally)
    if (!s_initialized) {
        ::fastCDC_init();
        s_initialized = true;
        LOG_INFO("FastCDC globally initialized");
    }
    
    // Set instance-specific parameters via global variables
    // Note: This is not thread-safe due to FastCDC's global variable design
    ::MinSize = min_size;
    ::MaxSize = max_size;
    ::expectCS = avg_size;
    
    LOG_INFO("FastCDC Chunker created: min=`, avg=`, max=`", min_size, avg_size, max_size);
}

FastCDCChunker::~FastCDCChunker() {
    // No cleanup needed as FastCDC uses static data
}

size_t FastCDCChunker::next_chunk(const unsigned char *data, size_t length) {
    if (data == nullptr) {
        LOG_ERROR("FastCDC next_chunk called with null data pointer");
        return 0;
    }
    
    if (length == 0) {
        return 0;
    }
    
    // Limit length to max_size to avoid buffer overrun
    size_t actual_length = length > m_max_size ? m_max_size : length;
    
    // Use normalized_chunking_64 from FastCDC-c library
    // It returns the size of the next chunk
    // Note: FastCDC expects int, so we need to cast
    if (actual_length > INT_MAX) {
        LOG_WARN("Length ` exceeds INT_MAX, truncating", actual_length);
        actual_length = INT_MAX;
    }
    
    int chunk_size = ::normalized_chunking_64(const_cast<unsigned char*>(data), (int)actual_length);
    
    if (chunk_size <= 0) {
        LOG_WARN("FastCDC returned invalid chunk size: `, using min_size", chunk_size);
        return m_min_size < length ? m_min_size : length;
    }
    
    // Ensure chunk size is within bounds
    if ((size_t)chunk_size < m_min_size) {
        size_t result = length < m_min_size ? length : m_min_size;
        LOG_DEBUG("Chunk size ` < min_size `, returning `", chunk_size, m_min_size, result);
        return result;
    }
    if ((size_t)chunk_size > m_max_size) {
        LOG_WARN("Chunk size ` > max_size `, capping to max", chunk_size, m_max_size);
        return m_max_size;
    }
    
    return chunk_size;
}

} // namespace ZFile
