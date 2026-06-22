import { createClient } from "@supabase/supabase-js";

const rawSupabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
const supabaseUrl = rawSupabaseUrl?.trim()
  ? rawSupabaseUrl.includes("://")
    ? rawSupabaseUrl.trim()
    : `https://${rawSupabaseUrl.trim()}`
  : undefined;

export const supabaseConfigStatus =
  supabaseUrl && supabasePublishableKey ? "configured" : "not-configured";

export const supabase =
  supabaseUrl && supabasePublishableKey
    ? createClient(supabaseUrl, supabasePublishableKey)
    : null;
