-- ══════════════════════════════════════════════════
-- FINSIGHT DATABASE SCHEMA
-- ══════════════════════════════════════════════════

-- 1. Users table (auth managed by Supabase Auth)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT UNIQUE,
  email TEXT UNIQUE,
  display_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_login TIMESTAMPTZ DEFAULT now()
);

-- 2. Raw SMS storage (dedup by sms_id + user_id)
CREATE TABLE IF NOT EXISTS sms_messages (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  sms_id TEXT NOT NULL,
  thread_id TEXT,
  sender TEXT,
  body TEXT,
  sms_type TEXT,
  timestamp BIGINT,
  date_sent BIGINT,
  read BOOLEAN DEFAULT false,
  service_center TEXT,
  label TEXT,
  sub_label TEXT,
  label_confidence REAL,
  is_spam BOOLEAN DEFAULT false,
  is_genuine BOOLEAN DEFAULT true,
  processed_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, sms_id)  -- prevents duplicate SMS on reinstall
);

-- 3. Transactions with full details
CREATE TABLE IF NOT EXISTS transactions (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  sms_id TEXT,
  sender TEXT,
  receiver TEXT,
  amount DECIMAL(15,2),
  transaction_type TEXT CHECK (transaction_type IN ('credit', 'debit')),
  payment_method TEXT,  -- UPI, NEFT, IMPS, RTGS, Card, Wallet, Other
  category TEXT DEFAULT 'other',  -- shopping, food, travel, bills, salary, etc.
  category_edited BOOLEAN DEFAULT false,  -- user manually edited?
  bank_name TEXT,
  account_number TEXT,
  counterparty TEXT,
  description TEXT,
  raw_body TEXT,
  transaction_date TIMESTAMPTZ,
  label TEXT,
  sub_label TEXT,
  label_confidence REAL,
  is_anomaly BOOLEAN DEFAULT false,
  anomaly_score REAL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, sms_id)
);

-- 4. Category definitions (user-editable)
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  icon TEXT DEFAULT 'category',
  color TEXT DEFAULT '#808080',
  is_system BOOLEAN DEFAULT true  -- false = user-created
);

-- Insert default categories
INSERT INTO categories (name, icon, color, is_system) VALUES
  ('shopping', 'shopping_bag', '#FF6B6B', true),
  ('food', 'restaurant', '#FFA726', true),
  ('travel', 'flight', '#42A5F5', true),
  ('bills', 'receipt', '#AB47BC', true),
  ('salary', 'account_balance_wallet', '#66BB6A', true),
  ('transfer', 'swap_horiz', '#26C6DA', true),
  ('entertainment', 'movie', '#EC407A', true),
  ('health', 'local_hospital', '#EF5350', true),
  ('education', 'school', '#5C6BC0', true),
  ('investment', 'trending_up', '#7CB342', true),
  ('emi', 'credit_card', '#FF7043', true),
  ('recharge', 'phone_android', '#78909C', true),
  ('other', 'help_outline', '#BDBDBD', true)
ON CONFLICT (name) DO NOTHING;

-- 5. ML training tracker
CREATE TABLE IF NOT EXISTS ml_training_log (
  id SERIAL PRIMARY KEY,
  total_sms_trained INT,
  accuracy REAL,
  f1_score REAL,
  triggered_by TEXT,  -- 'threshold' or 'manual'
  new_sms_count INT,
  trained_at TIMESTAMPTZ DEFAULT now()
);

-- 6. AI chat history
CREATE TABLE IF NOT EXISTS ai_conversations (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT,
  web_sources JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE sms_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;

-- RLS Policies (users only see their own data)
CREATE POLICY "Users see own SMS"
  ON sms_messages FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users see own transactions"
  ON transactions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users see own AI chats"
  ON ai_conversations FOR ALL USING (auth.uid() = user_id);

-- Indexes for performance
CREATE INDEX idx_sms_user ON sms_messages(user_id);
CREATE INDEX idx_txn_user ON transactions(user_id);
CREATE INDEX idx_txn_date ON transactions(transaction_date);
CREATE INDEX idx_txn_category ON transactions(category);
