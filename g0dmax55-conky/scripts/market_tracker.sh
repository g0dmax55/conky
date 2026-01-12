#!/bin/bash

# Market Tracker Script for Conky - Enhanced Version
# Features: Crypto, Indices, Stocks with % change, Gold/Silver, Market Status

# Conky Colors
C6="\${color6}"  # Red - Tree/Brackets/Bearish
C2="\${color2}"  # Cyan - Values
C3="\${color3}"  # Green - Bullish/Up
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

# Cache directory
CACHE_DIR="/tmp/conky_markets"
mkdir -p "$CACHE_DIR"

# Cache timeout in seconds
CACHE_TIMEOUT=60
CACHE_TIMEOUT_LONG=120

# Function to get cached data or fetch new
get_cached() {
    local cache_file="$CACHE_DIR/$1"
    local url="$2"
    local timeout="${3:-$CACHE_TIMEOUT}"
    
    # Check if cache exists and is fresh
    if [ -f "$cache_file" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [ $age -lt $timeout ]; then
            cat "$cache_file"
            return
        fi
    fi
    
    # Fetch new data
    local data=$(curl -s --max-time 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "$url" 2>/dev/null)
    if [ -n "$data" ] && [ "$data" != "null" ]; then
        echo "$data" > "$cache_file"
        echo "$data"
    elif [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        echo ""
    fi
}

# Function to format percentage with arrow and COLOR (FIXED)
format_percent_colored() {
    local pct=$1
    local arrow=""
    local sign=""
    local color=""
    
    # Use awk for reliable comparison
    local is_positive=$(echo "$pct" | awk '{if ($1 > 0.001) print 1; else print 0}')
    local is_negative=$(echo "$pct" | awk '{if ($1 < -0.001) print 1; else print 0}')
    
    if [ "$is_positive" = "1" ]; then
        arrow="↑"
        sign="+"
        color="${C3}"  # Green for bullish
    elif [ "$is_negative" = "1" ]; then
        arrow="↓"
        sign=""
        color="${C6}"  # Red for bearish
    else
        arrow="─"
        sign=""
        color="${C2}"  # Cyan for neutral
    fi
    
    printf "%s%s%.1f%% %s${CR}" "$color" "$sign" "$pct" "$arrow"
}

# Function to check if Indian market is open
is_market_open() {
    local day=$(date +%u)  # 1=Monday, 7=Sunday
    local hour=$(date +%H)
    local minute=$(date +%M)
    local current_time=$((hour * 60 + minute))
    
    # Market hours: 9:15 AM - 3:30 PM IST, Mon-Fri
    local open_time=$((9 * 60 + 15))   # 9:15 AM
    local close_time=$((15 * 60 + 30)) # 3:30 PM
    
    if [ $day -ge 1 ] && [ $day -le 5 ]; then
        if [ $current_time -ge $open_time ] && [ $current_time -le $close_time ]; then
            echo "OPEN"
            return
        fi
    fi
    echo "CLOSED"
}

# ===== HEADER WITH MARKET STATUS =====
MARKET_STATUS=$(is_market_open)
if [ "$MARKET_STATUS" = "OPEN" ]; then
    STATUS_COLOR="${C3}"  # Green
else
    STATUS_COLOR="${C6}"  # Red
fi
echo "${C6}├─${CR} ${C6}[${C2}MARKETS${C6}]${CR} ${C6}[${C2}$(date '+%I:%M %p')${C6}]${CR} ${C6}[${STATUS_COLOR}${MARKET_STATUS}${C6}]${CR}"
echo "${C6}│${CR}"

# ===== CRYPTO SECTION (5 coins) =====
echo "${C6}├─${CR} ${C1}crypto${CR} ${C6}─┤${CR}"

# Fetch crypto data from CoinGecko (free, no API key)
# Note: CoinGecko IDs are: bitcoin, ethereum, ripple, solana, dogecoin
CRYPTO_DATA=$(get_cached "crypto_all.json" "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,ripple,solana,dogecoin&vs_currencies=inr&include_24hr_change=true")

if [ -n "$CRYPTO_DATA" ]; then
    # Define crypto mappings: coingecko_id:display_symbol
    declare -A CRYPTO_MAP
    CRYPTO_MAP=( ["bitcoin"]="BTC" ["ethereum"]="ETH" ["ripple"]="XRP" ["solana"]="SOL" ["dogecoin"]="DOGE" )
    CRYPTO_ORDER=("bitcoin" "ethereum" "ripple" "solana" "dogecoin")
    
    for ID in "${CRYPTO_ORDER[@]}"; do
        SYMBOL="${CRYPTO_MAP[$ID]}"
        
        # Extract price using more flexible pattern
        PRICE=$(echo "$CRYPTO_DATA" | sed 's/},"/}\n"/g' | grep "\"$ID\"" | grep -o '"inr":[0-9.]*' | cut -d: -f2)
        CHANGE=$(echo "$CRYPTO_DATA" | sed 's/},"/}\n"/g' | grep "\"$ID\"" | grep -o '"inr_24h_change":[0-9.-]*' | cut -d: -f2)
        
        if [ -n "$PRICE" ]; then
            PRICE_FMT=$(printf "₹%.0f" "$PRICE" 2>/dev/null || echo "₹--")
            CHG_FMT=$(format_percent_colored "${CHANGE:-0}")
            printf "${C6}│  ├─${CR} ${C1}%-5s${CR} ${C6}[${C2}%s${C6}]${CR} ${C6}[%s${C6}]${CR}\n" "${SYMBOL}:" "$PRICE_FMT" "$CHG_FMT"
        else
            printf "${C6}│  ├─${CR} ${C1}%-5s${CR} ${C6}[${C2}--${C6}]${CR}\n" "${SYMBOL}:"
        fi
    done
else
    echo "${C6}│  ├─${CR} ${C1}crypto:${CR} ${C6}[${C2}-- offline --${C6}]${CR}"
fi

echo "${C6}│${CR}"

# ===== GOLD & SILVER SECTION =====
echo "${C6}├─${CR} ${C1}metals${CR} ${C6}─┤${CR}"

# Fetch Gold price (PAX Gold tracks gold spot price per oz)
GOLD_DATA=$(get_cached "gold.json" "https://api.coingecko.com/api/v3/simple/price?ids=pax-gold&vs_currencies=inr&include_24hr_change=true")

if [ -n "$GOLD_DATA" ]; then
    GOLD_OZ=$(echo "$GOLD_DATA" | grep -o '"inr":[0-9.]*' | cut -d: -f2)
    GOLD_CHANGE=$(echo "$GOLD_DATA" | grep -o '"inr_24h_change":[0-9.-]*' | cut -d: -f2)
    
    if [ -n "$GOLD_OZ" ]; then
        # Convert from per oz (31.1g) to per gram and per pavan (8g)
        GOLD_GRAM=$(echo "$GOLD_OZ" | awk '{printf "%.0f", $1 / 31.1}')
        GOLD_SOV=$(echo "$GOLD_GRAM" | awk '{printf "%.0f", $1 * 8}')
        GOLD_CHG=$(format_percent_colored "${GOLD_CHANGE:-0}")
        
        echo "${C6}│  ├─${CR} ${C1}GOLD:${CR} ${C6}[${C2}₹${GOLD_GRAM}/g${C6}]${CR} ${C6}[${C2}₹${GOLD_SOV}/sovereign${C6}]${CR} ${C6}[${GOLD_CHG}${C6}]${CR}"
        
        # Calculate Silver (Gold/Silver ratio is ~82)
        SILVER_OZ=$(echo "$GOLD_OZ" | awk '{printf "%.0f", $1 / 82}')
        SILVER_GRAM=$(echo "$SILVER_OZ" | awk '{printf "%.0f", $1 / 31.1}')
        SILVER_SOV=$(echo "$SILVER_GRAM" | awk '{printf "%.0f", $1 * 8}')
        SILVER_CHG=$(format_percent_colored "${GOLD_CHANGE:-0}")
        
        if [ "$SILVER_GRAM" != "0" ] && [ -n "$SILVER_GRAM" ]; then
            echo "${C6}│  ├─${CR} ${C1}SILVER:${CR} ${C6}[${C2}₹${SILVER_GRAM}/g${C6}]${CR} ${C6}[${C2}₹${SILVER_SOV}/sovereign${C6}]${CR} ${C6}[${SILVER_CHG}${C6}]${CR}"
        else
            echo "${C6}│  ├─${CR} ${C1}SILVER:${CR} ${C6}[${C2}--${C6}]${CR}"
        fi
    else
        echo "${C6}│  ├─${CR} ${C1}GOLD:${CR} ${C6}[${C2}--${C6}]${CR}"
        echo "${C6}│  ├─${CR} ${C1}SILVER:${CR} ${C6}[${C2}--${C6}]${CR}"
    fi
else
    echo "${C6}│  ├─${CR} ${C1}GOLD:${CR} ${C6}[${C2}-- offline --${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}SILVER:${CR} ${C6}[${C2}-- offline --${C6}]${CR}"
fi

echo "${C6}│${CR}"

# ===== INDICES SECTION =====
echo "${C6}├─${CR} ${C1}indices${CR} ${C6}─┤${CR}"

# Function to fetch stock price and change from Google Finance
fetch_google_finance() {
    local symbol=$1
    local cache_file="$CACHE_DIR/${symbol//:/}.cache"
    
    # Check cache first
    if [ -f "$cache_file" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [ $age -lt $CACHE_TIMEOUT_LONG ]; then
            cat "$cache_file"
            return
        fi
    fi
    
    # Fetch from Google Finance
    local page=$(curl -s --max-time 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "https://www.google.com/finance/quote/${symbol}" 2>/dev/null)
    
    # Extract using HTML classes (Google Finance changed structure)
    # Price is in <div class="YMlKec fxKbKc">
    local price_raw=$(echo "$page" | grep -oP '<div class="YMlKec fxKbKc">\K[^<]+' | head -1)
    local price=$(echo "$price_raw" | tr -d ',')
    
    # Change/Percent is in subsequent aria-label, e.g. aria-label="Down by 0.47%"
    # We use price_raw as anchor because it appears multiple times but correct one is followed by label
    # Updated Regex: Search for label containing '%' to avoid "Key events" label in stocks
    local label=""
    if [ -n "$price_raw" ]; then
        # Escape special chars in price for regex
        local price_esc=$(echo "$price_raw" | sed 's/[.[\*^$]/\\&/g')
        label=$(echo "$page" | grep -oP "${price_esc}.*?aria-label=\"\K[^\"]*?[0-9.]+%[^\"]*" | head -1)
    fi
    
    local pct=$(echo "$label" | grep -oE '[0-9.]+' | head -1)
    
    # Add delay to avoid rate limiting
    sleep 1.5
    
    # Determine sign from label text
    if echo "$label" | grep -q "Down"; then
        pct="-${pct}"
    fi

    local change="0" # Absolute change not displayed, so 0 is fine
    
    if [ -n "$price" ]; then
        echo "${price}|${change:-0}|${pct:-0}" > "$cache_file"
        echo "${price}|${change:-0}|${pct:-0}"
    elif [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        echo ""
    fi
}

# NIFTY 50
NIFTY=$(fetch_google_finance "NIFTY_50:INDEXNSE")
if [ -n "$NIFTY" ]; then
    NIFTY_PRICE=$(echo "$NIFTY" | cut -d'|' -f1)
    NIFTY_PCT=$(echo "$NIFTY" | cut -d'|' -f3)
    NIFTY_CHG=$(format_percent_colored "${NIFTY_PCT:-0}")
    printf "${C6}│  ├─${CR} ${C1}NIFTY50:${CR} ${C6}[${C2}%s${C6}]${CR} ${C6}[%s${C6}]${CR}\n" "$NIFTY_PRICE" "$NIFTY_CHG"
else
    echo "${C6}│  ├─${CR} ${C1}NIFTY50:${CR} ${C6}[${C2}--${C6}]${CR}"
fi

# SENSEX
SENSEX=$(fetch_google_finance "SENSEX:INDEXBOM")
if [ -n "$SENSEX" ]; then
    SENSEX_PRICE=$(echo "$SENSEX" | cut -d'|' -f1)
    SENSEX_PCT=$(echo "$SENSEX" | cut -d'|' -f3)
    SENSEX_CHG=$(format_percent_colored "${SENSEX_PCT:-0}")
    printf "${C6}│  ├─${CR} ${C1}SENSEX:${CR} ${C6}[${C2}%s${C6}]${CR} ${C6}[%s${C6}]${CR}\n" "$SENSEX_PRICE" "$SENSEX_CHG"
else
    echo "${C6}│  ├─${CR} ${C1}SENSEX:${CR} ${C6}[${C2}--${C6}]${CR}"
fi

# BANKNIFTY
BANKNIFTY=$(fetch_google_finance "NIFTY_BANK:INDEXNSE")
if [ -n "$BANKNIFTY" ]; then
    BANKNIFTY_PRICE=$(echo "$BANKNIFTY" | cut -d'|' -f1)
    BANKNIFTY_PCT=$(echo "$BANKNIFTY" | cut -d'|' -f3)
    BANKNIFTY_CHG=$(format_percent_colored "${BANKNIFTY_PCT:-0}")
    printf "${C6}│  ├─${CR} ${C1}BANKNIFTY:${CR} ${C6}[${C2}%s${C6}]${CR} ${C6}[%s${C6}]${CR}\n" "$BANKNIFTY_PRICE" "$BANKNIFTY_CHG"
else
    echo "${C6}│  ├─${CR} ${C1}BANKNIFTY:${CR} ${C6}[${C2}--${C6}]${CR}"
fi

echo "${C6}│${CR}"

# ===== TOP STOCKS SECTION WITH % CHANGE =====
echo "${C6}├─${CR} ${C1}top_stocks${CR} ${C6}─┤${CR}"

# Fetch top Nifty 50 stocks
STOCKS=("RELIANCE:NSE" "TCS:NSE" "HDFCBANK:NSE" "INFY:NSE" "ICICIBANK:NSE")
STOCK_NAMES=("RELIANCE" "TCS" "HDFCBANK" "INFY" "ICICIBANK")

for i in "${!STOCKS[@]}"; do
    STOCK=${STOCKS[$i]}
    NAME=${STOCK_NAMES[$i]}
    
    STOCK_DATA=$(fetch_google_finance "$STOCK")
    
    if [ -n "$STOCK_DATA" ]; then
        STOCK_PRICE=$(echo "$STOCK_DATA" | cut -d'|' -f1)
        STOCK_PCT=$(echo "$STOCK_DATA" | cut -d'|' -f3)
        STOCK_CHG=$(format_percent_colored "${STOCK_PCT:-0}")
        printf "${C6}│  ├─${CR} ${C1}%-10s${CR} ${C6}[${C2}%s${C6}]${CR} ${C6}[%s${C6}]${CR}\n" "${NAME}:" "$STOCK_PRICE" "$STOCK_CHG"
    else
        printf "${C6}│  ├─${CR} ${C1}%-10s${CR} ${C6}[${C2}--${C6}]${CR}\n" "${NAME}:"
    fi
done

echo "${C6}└─${CR}"
