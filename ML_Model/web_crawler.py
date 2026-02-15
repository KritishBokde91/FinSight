"""
web_crawler.py — Smart Web Crawler for AI Insights
====================================================
Uses DuckDuckGo for search and trafilatura for content extraction.
Works with ANY website layout — no CSS-specific rules needed.
"""

import re
import json
from typing import List, Dict, Optional
from urllib.parse import quote_plus

try:
    import trafilatura
    HAS_TRAFILATURA = True
except ImportError:
    HAS_TRAFILATURA = False
    print("[WebCrawler] trafilatura not installed. Install: pip install trafilatura")

try:
    from duckduckgo_search import DDGS
    HAS_DDGS = True
except ImportError:
    HAS_DDGS = False
    print("[WebCrawler] duckduckgo_search not installed. Install: pip install duckduckgo-search")

import requests


class WebCrawler:
    """Smart web crawler that extracts content from any website."""
    
    def __init__(self, max_results: int = 5, max_content_length: int = 2000):
        self.max_results = max_results
        self.max_content_length = max_content_length
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        })
    
    def search(self, query: str) -> List[Dict]:
        """
        Search using DuckDuckGo and return results with URLs.
        Returns list of {title, url, snippet}.
        """
        if not HAS_DDGS:
            return self._fallback_search(query)
        
        try:
            with DDGS() as ddgs:
                results = list(ddgs.text(query, max_results=self.max_results))
            
            return [
                {
                    'title': r.get('title', ''),
                    'url': r.get('href', r.get('link', '')),
                    'snippet': r.get('body', ''),
                }
                for r in results
            ]
        except Exception as e:
            print(f"[WebCrawler] Search error: {e}")
            return self._fallback_search(query)
    
    def _fallback_search(self, query: str) -> List[Dict]:
        """Fallback search using DuckDuckGo HTML."""
        try:
            url = f"https://html.duckduckgo.com/html/?q={quote_plus(query)}"
            resp = self.session.get(url, timeout=10)
            
            # Simple regex extraction from DDG HTML
            results = []
            links = re.findall(
                r'<a rel="nofollow" class="result__a" href="(.*?)".*?>(.*?)</a>.*?'
                r'<a class="result__snippet".*?>(.*?)</a>',
                resp.text, re.DOTALL
            )
            
            for href, title, snippet in links[:self.max_results]:
                results.append({
                    'title': re.sub(r'<.*?>', '', title).strip(),
                    'url': href,
                    'snippet': re.sub(r'<.*?>', '', snippet).strip(),
                })
            
            return results
        except Exception as e:
            print(f"[WebCrawler] Fallback search error: {e}")
            return []
    
    def extract_content(self, url: str) -> Optional[str]:
        """
        Extract main content from a URL using trafilatura.
        This handles ANY website layout — no CSS rules needed.
        """
        if not HAS_TRAFILATURA:
            return self._simple_extract(url)
        
        try:
            downloaded = trafilatura.fetch_url(url)
            if downloaded:
                text = trafilatura.extract(
                    downloaded,
                    include_comments=False,
                    include_tables=True,
                    no_fallback=False,
                )
                if text:
                    # Truncate to max length
                    return text[:self.max_content_length]
            return None
        except Exception as e:
            print(f"[WebCrawler] Extract error for {url}: {e}")
            return None
    
    def _simple_extract(self, url: str) -> Optional[str]:
        """Simple fallback text extraction."""
        try:
            resp = self.session.get(url, timeout=10)
            # Strip HTML tags
            text = re.sub(r'<script.*?</script>', '', resp.text, flags=re.DOTALL)
            text = re.sub(r'<style.*?</style>', '', text, flags=re.DOTALL)
            text = re.sub(r'<.*?>', ' ', text)
            text = re.sub(r'\s+', ' ', text).strip()
            return text[:self.max_content_length] if text else None
        except Exception as e:
            print(f"[WebCrawler] Simple extract error: {e}")
            return None
    
    def search_and_extract(self, query: str) -> List[Dict]:
        """
        Search + extract content from top results.
        Returns list of {title, url, snippet, content}.
        """
        search_results = self.search(query)
        enriched = []
        
        for result in search_results:
            content = self.extract_content(result['url'])
            enriched.append({
                **result,
                'content': content or result.get('snippet', ''),
                'extracted': content is not None,
            })
        
        return enriched
    
    def search_financial(self, query: str) -> List[Dict]:
        """Search with financial context for better results."""
        # Add financial keywords if not present
        financial_terms = ['stock', 'invest', 'market', 'nifty', 'sensex', 'mutual fund']
        has_financial = any(term in query.lower() for term in financial_terms)
        
        if not has_financial:
            query = f"{query} India finance"
        
        return self.search_and_extract(query)


# ─── LLM Query Analysis ─────────────────────────────────────────────────

def should_crawl_web(user_query: str, llm_model=None) -> List[str]:
    """
    Determine if a query needs web crawling.
    Returns list of search queries (empty = no crawl needed).
    
    Uses LLM if available, otherwise rule-based.
    """
    query_lower = user_query.lower()
    
    # Rule-based triggers for web crawling
    WEB_TRIGGERS = [
        # Stock/market queries
        (r'\b(?:stock|share|nifty|sensex|bse|nse)\b.*(?:price|today|current|buy|sell)',
         lambda q: [f"{q} stock price today India"]),
        
        # Investment queries  
        (r'\b(?:invest|sip|mutual\s*fund)\b.*(?:best|suggest|recommend)',
         lambda q: [f"best {q} 2025 India", f"{q} recommendations"]),
        
        # News/current events
        (r'\b(?:news|latest|recent|today|current)\b.*(?:market|economy|rbi|budget)',
         lambda q: [f"latest {q} India"]),
        
        # Rate queries
        (r'\b(?:interest\s*rate|fd\s*rate|loan\s*rate|repo\s*rate)\b',
         lambda q: [f"current {q} India 2025"]),
        
        # Tax queries
        (r'\b(?:tax|gst|income\s*tax|deduction)\b.*(?:slab|rate|save|rule)',
         lambda q: [f"{q} India 2025"]),
        
        # Crypto
        (r'\b(?:bitcoin|crypto|ethereum)\b',
         lambda q: [f"{q} price today", f"{q} India regulation"]),
    ]
    
    for pattern, query_gen in WEB_TRIGGERS:
        if re.search(pattern, query_lower):
            return query_gen(user_query)
    
    # If LLM is available, ask it
    if llm_model:
        try:
            prompt = (
                "Analyze this user query and decide if it needs live web data. "
                "If yes, return JSON: {\"search_queries\": [\"query1\", \"query2\"]}. "
                "If no, return: {\"search_queries\": []}. "
                "Only return JSON, nothing else.\n\n"
                f"User query: {user_query}"
            )
            
            response = ""
            for chunk in llm_model.stream_response(prompt):
                response += chunk
            
            # Parse JSON from response
            match = re.search(r'\{[^}]+\}', response)
            if match:
                data = json.loads(match.group())
                return data.get('search_queries', [])
        except Exception as e:
            print(f"[WebCrawler] LLM decision error: {e}")
    
    return []


# Singleton
crawler = WebCrawler()
