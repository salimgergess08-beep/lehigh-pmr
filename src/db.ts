import { createClient } from '@supabase/supabase-js';
export const db = createClient('https://jqkoejmtkvclfakrcpeh.supabase.co','sb_publishable_K3cEFH-DagBFxsYDiYDeqw_3lZ6Q5n9');
export type Listing = {id: string; title: string; address: string; city: string; price: number; beds: number; baths: number; sqft: number | null; property_type: string; description: string; amenities: string; images: string[]; status: string; available_date: string | null; revision?: number; created_at?: string};
export type Settings = {phone: string; email: string; address: string};
export const money = (n: number) => new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0}).format(n);
export function check(error: {message: string} | null) { if(error) throw new Error(error.message); }
