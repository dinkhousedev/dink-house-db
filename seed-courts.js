const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://wchxzbuuwssrnaxshseu.supabase.co';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjaHh6YnV1d3Nzcm5heHNoc2V1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODk5MDg3NywiZXhwIjoyMDc0NTY2ODc3fQ.6u66CMI4K4xb1R3-xbEHkW5TeQ9tXeA420WyMnW-d5I';

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function seedCourts() {
  console.log('Seeding courts...\n');

  const courts = [
    { court_number: 1, name: 'Court 1 Indoor', surface_type: 'hard', environment: 'indoor', status: 'available', location: 'Indoor Pavilion', max_capacity: 4 },
    { court_number: 2, name: 'Court 2 Indoor', surface_type: 'hard', environment: 'indoor', status: 'available', location: 'Indoor Pavilion', max_capacity: 4 },
    { court_number: 3, name: 'Court 3 Indoor', surface_type: 'hard', environment: 'indoor', status: 'available', location: 'Indoor Pavilion', max_capacity: 4 },
    { court_number: 4, name: 'Court 4 Indoor', surface_type: 'hard', environment: 'indoor', status: 'available', location: 'Indoor Pavilion', max_capacity: 4 },
    { court_number: 5, name: 'Court 5 Indoor', surface_type: 'hard', environment: 'indoor', status: 'available', location: 'Indoor Pavilion', max_capacity: 4 },
    { court_number: 6, name: 'Court 6 Outdoor', surface_type: 'hard', environment: 'outdoor', status: 'available', location: 'Championship Plaza', max_capacity: 4 },
    { court_number: 7, name: 'Court 7 Outdoor', surface_type: 'hard', environment: 'outdoor', status: 'available', location: 'Championship Plaza', max_capacity: 4 },
    { court_number: 8, name: 'Court 8 Outdoor', surface_type: 'hard', environment: 'outdoor', status: 'available', location: 'Championship Plaza', max_capacity: 4 },
    { court_number: 9, name: 'Court 9 Outdoor', surface_type: 'hard', environment: 'outdoor', status: 'available', location: 'Championship Plaza', max_capacity: 4 },
    { court_number: 10, name: 'Court 10 Outdoor', surface_type: 'hard', environment: 'outdoor', status: 'available', location: 'Championship Plaza', max_capacity: 4 }
  ];

  // First, let's check if any courts exist
  const { data: existingCourts } = await supabase
    .from('courts_view')
    .select('court_number');

  console.log('Existing courts:', existingCourts?.length || 0);

  // Use the RPC endpoint to directly insert into events.courts schema
  // Since courts_view is read-only, we need to insert via the service role
  const { data, error } = await supabase
    .schema('events')
    .from('courts')
    .upsert(courts, {
      onConflict: 'court_number',
      ignoreDuplicates: false
    })
    .select();

  if (error) {
    console.error('Error seeding courts:', error);
    return;
  }

  console.log('Successfully seeded', data?.length || 0, 'courts');

  // Verify the courts are now accessible via courts_view
  const { data: viewData, error: viewError } = await supabase
    .from('courts_view')
    .select('*')
    .order('court_number');

  console.log('\nVerification - courts in courts_view:', viewData?.length || 0);
  if (viewError) {
    console.error('View error:', viewError);
  }

  if (viewData && viewData.length > 0) {
    console.log('\nFirst 3 courts:');
    viewData.slice(0, 3).forEach(court => {
      console.log(`- Court ${court.court_number}: ${court.name} (${court.environment})`);
    });
  }
}

seedCourts().catch(console.error);
