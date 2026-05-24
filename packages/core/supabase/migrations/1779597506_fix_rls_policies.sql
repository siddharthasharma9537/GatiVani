-- Fix RLS policies for extracted_texts table to allow anon API access

-- Drop existing restrictive INSERT policy
DROP POLICY IF EXISTS "extracted_texts_insert_authenticated" ON public.extracted_texts;

-- Create new policy that allows anyone to insert
CREATE POLICY "extracted_texts_insert_public"
  ON public.extracted_texts
  FOR INSERT
  WITH CHECK (TRUE);
