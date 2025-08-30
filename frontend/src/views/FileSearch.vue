<template>
  <div class="file-search">
    <div class="search-header">
      <h1>File Search</h1>
      <p>Search through your indexed documents using semantic search</p>
    </div>

    <div class="search-container">
      <div class="search-box">
        <input 
          v-model="searchQuery" 
          @keyup.enter="performSearch"
          type="text" 
          placeholder="Enter your search query..." 
          class="search-input"
          :disabled="isSearching"
        />
        <button 
          @click="performSearch" 
          class="search-button"
          :disabled="isSearching || !searchQuery.trim()"
        >
          <span v-if="isSearching">Searching...</span>
          <span v-else>Search</span>
        </button>
      </div>

      <div class="search-options">
        <label class="option">
          Max Results:
          <select v-model="maxResults">
            <option value="5">5</option>
            <option value="10">10</option>
            <option value="20">20</option>
            <option value="50">50</option>
          </select>
        </label>
      </div>
    </div>

    <div v-if="error" class="error-message">
      <p>{{ error }}</p>
    </div>

    <div v-if="results.length > 0" class="search-results">
      <div class="results-header">
        <h2>Search Results ({{ results.length }})</h2>
        <p v-if="searchPerformed">Results for: "<strong>{{ lastSearchQuery }}</strong>"</p>
      </div>

      <div class="results-list">
        <div 
          v-for="result in results" 
          :key="result.id || result.file_path"
          class="result-item"
        >
          <div class="result-header">
            <h3 class="result-title">{{ result.file_name || extractFileName(result.file_path) }}</h3>
            <div class="result-meta">
              <span class="result-score">Score: {{ (result.score * 100).toFixed(1) }}%</span>
              <span class="result-path">{{ result.file_path }}</span>
            </div>
          </div>

          <div v-if="result.content" class="result-content">
            <p>{{ result.content }}</p>
          </div>

          <div v-if="result.metadata" class="result-metadata">
            <span v-for="(value, key) in result.metadata" :key="key" class="metadata-item">
              <strong>{{ key }}:</strong> {{ value }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <div v-else-if="searchPerformed && !isSearching" class="no-results">
      <p>No results found for "{{ lastSearchQuery }}". Try different search terms.</p>
    </div>

    <div v-if="!searchPerformed && !isSearching" class="search-help">
      <h3>Search Tips</h3>
      <ul>
        <li>Use natural language queries</li>
        <li>Try different keywords and phrases</li>
        <li>Search is powered by semantic understanding</li>
        <li>Results are ranked by relevance</li>
      </ul>
    </div>
  </div>
</template>

<script>
import { ref } from 'vue'
import { api } from '../services/api'

export default {
  name: 'FileSearch',
  setup() {
    const searchQuery = ref('')
    const maxResults = ref(10)
    const results = ref([])
    const isSearching = ref(false)
    const error = ref('')
    const searchPerformed = ref(false)
    const lastSearchQuery = ref('')

    const performSearch = async () => {
      if (!searchQuery.value.trim()) return

      isSearching.value = true
      error.value = ''
      lastSearchQuery.value = searchQuery.value.trim()

      try {
        const response = await api.searchFiles(searchQuery.value.trim(), maxResults.value)
        
        if (response.success !== false) {
          results.value = response.results || []
          searchPerformed.value = true
        } else {
          error.value = response.error || 'Search failed'
          results.value = []
        }
      } catch (err) {
        error.value = 'Search failed: ' + err.message
        results.value = []
      } finally {
        isSearching.value = false
      }
    }

    const extractFileName = (filePath) => {
      if (!filePath) return 'Unknown File'
      const parts = filePath.split('/')
      return parts[parts.length - 1] || filePath
    }

    return {
      searchQuery,
      maxResults,
      results,
      isSearching,
      error,
      searchPerformed,
      lastSearchQuery,
      performSearch,
      extractFileName
    }
  }
}
</script>

<style scoped>
.file-search {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2rem;
}

.search-header {
  text-align: center;
  margin-bottom: 2rem;
}

.search-header h1 {
  color: var(--color-heading);
  margin-bottom: 0.5rem;
}

.search-header p {
  color: var(--color-text-muted);
}

.search-container {
  background: var(--color-background-soft);
  border-radius: 12px;
  padding: 1.5rem;
  margin-bottom: 2rem;
}

.search-box {
  display: flex;
  gap: 1rem;
  margin-bottom: 1rem;
}

.search-input {
  flex: 1;
  padding: 0.75rem;
  border: 2px solid var(--color-border);
  border-radius: 8px;
  font-size: 1rem;
  background: var(--color-background);
  color: var(--color-text);
}

.search-input:focus {
  outline: none;
  border-color: var(--color-brand);
}

.search-input:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.search-button {
  padding: 0.75rem 1.5rem;
  background: var(--color-brand);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 1rem;
  cursor: pointer;
  transition: background 0.3s;
}

.search-button:hover:not(:disabled) {
  background: var(--color-brand-dark);
}

.search-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.search-options {
  display: flex;
  gap: 1rem;
}

.option {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--color-text);
}

.option select {
  padding: 0.25rem 0.5rem;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  background: var(--color-background);
  color: var(--color-text);
}

.error-message {
  background: #fee;
  color: #c33;
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
}

.search-results {
  margin-top: 2rem;
}

.results-header {
  margin-bottom: 1.5rem;
}

.results-header h2 {
  color: var(--color-heading);
  margin-bottom: 0.5rem;
}

.results-list {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.result-item {
  background: var(--color-background-soft);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  padding: 1.5rem;
  transition: transform 0.2s, box-shadow 0.2s;
}

.result-item:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.result-header {
  display: flex;
  justify-content: between;
  align-items: flex-start;
  margin-bottom: 1rem;
}

.result-title {
  color: var(--color-heading);
  margin: 0;
  font-size: 1.1rem;
}

.result-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.25rem;
  font-size: 0.9rem;
  color: var(--color-text-muted);
}

.result-score {
  background: var(--color-brand);
  color: white;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  font-weight: 500;
}

.result-path {
  font-family: monospace;
}

.result-content {
  margin: 1rem 0;
  padding: 1rem;
  background: var(--color-background);
  border-radius: 6px;
  color: var(--color-text);
  line-height: 1.6;
}

.result-metadata {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  margin-top: 1rem;
  font-size: 0.9rem;
}

.metadata-item {
  color: var(--color-text-muted);
}

.no-results {
  text-align: center;
  padding: 2rem;
  color: var(--color-text-muted);
}

.search-help {
  background: var(--color-background-soft);
  border-radius: 8px;
  padding: 1.5rem;
  margin-top: 2rem;
}

.search-help h3 {
  color: var(--color-heading);
  margin-bottom: 1rem;
}

.search-help ul {
  color: var(--color-text);
  line-height: 1.6;
}

.search-help li {
  margin-bottom: 0.5rem;
}

@media (max-width: 768px) {
  .file-search {
    padding: 1rem;
  }
  
  .search-box {
    flex-direction: column;
  }
  
  .result-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }
  
  .result-meta {
    align-items: flex-start;
  }
}
</style>