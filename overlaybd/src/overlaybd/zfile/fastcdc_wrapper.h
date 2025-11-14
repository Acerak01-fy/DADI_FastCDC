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

#pragma once

#include <cstdint>
#include <cstddef>

namespace ZFile {

/**
 * FastCDC Wrapper for C++ integration
 * 
 * This wrapper provides a clean C++ interface to the FastCDC-c library.
 */
class FastCDCChunker {
public:
    FastCDCChunker(uint32_t min_size = 2048, 
                   uint32_t avg_size = 8192, 
                   uint32_t max_size = 65536);
    
    ~FastCDCChunker();
    
    /**
     * Calculate the next chunk boundary
     * 
     * @param data      Pointer to the data buffer
     * @param length    Length of available data
     * @return          Size of the next chunk (in bytes)
     */
    size_t next_chunk(const unsigned char *data, size_t length);
    
    /**
     * Get configured sizes
     */
    uint32_t get_min_size() const { return m_min_size; }
    uint32_t get_avg_size() const { return m_avg_size; }
    uint32_t get_max_size() const { return m_max_size; }
    
private:
    uint32_t m_min_size;
    uint32_t m_avg_size;
    uint32_t m_max_size;
    static bool s_initialized;  // Static initialization flag
};

} // namespace ZFile
