import { checkSupabase } from '../backend/src/supabase.js';
try {
  console.log(JSON.stringify(await checkSupabase(), null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
