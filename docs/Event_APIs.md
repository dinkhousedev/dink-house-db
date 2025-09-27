 Here's a list of curl commands for different event types supported by your API:

  1. DUPR Open Play Event

  curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "DUPR Open Play Session",
      "eventType": "dupr_open_play",
      "startTime": "2025-10-20T14:00:00-04:00",
      "endTime": "2025-10-20T16:00:00-04:00",
      "courtIds": ["168ffb84-835a-464a-99fe-1da697b3d134", "be78adcb-1048-4656-b779-256a10d81a28"],
      "maxCapacity": 20,
      "minCapacity": 4,
      "duprRange": {
        "label": "2.0-3.2 Players",
        "minRating": 2.0,
        "maxRating": 3.2,
        "minInclusive": true,
        "maxInclusive": true
      }
    }'

  2. DUPR Tournament - good

  curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "Fall DUPR Championship",
      "eventType": "dupr_tournament",
      "description": "Competitive tournament for intermediate players",
      "startTime": "2025-11-01T08:00:00-04:00",
      "endTime": "2025-11-01T18:00:00-04:00",
      "courtIds": ["e2123a79-7ea7-41e6-a5ea-ea2282118d9b", 
  "20777d3c-8a4c-4501-bc53-21e5b377d7eb", "03a3906c-50dd-4ceb-9e8d-3ccdb5245f47"],
      "maxCapacity": 32,
      "minCapacity": 16,
      "priceMember": 45,
      "priceGuest": 60,
      "duprRange": {
        "label": "4.0+ Advanced",
        "minRating": 4.0,
        "openEnded": true,
        "minInclusive": true
      }
    }'

  3. Non-DUPR Tournament - good

  curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "Beginners Welcome Tournament",
      "eventType": "non_dupr_tournament",
      "description": "Fun tournament for new players - no rating required",
      "startTime": "2025-10-25T09:00:00-04:00",
      "endTime": "2025-10-25T14:00:00-04:00",
      "courtIds": ["3102058a-93b4-4fb5-91b7-0a303b67ac4d"],
      "maxCapacity": 24,
      "minCapacity": 8,
      "skillLevels": ["3.5", "4.0"],
      "priceMember": 25,
      "priceGuest": 35,
      "equipmentProvided": true
    }'

  4. League Play - good

  curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "Thursday Night League - Week 3",
      "eventType": "league",
      "description": "Weekly league play for registered teams",
      "startTime": "2025-10-17T18:30:00-04:00",
      "endTime": "2025-10-17T21:00:00-04:00",
      "courtIds": ["27f396f4-f18e-4c76-b341-b0a11c4b1411", "9fe25f36-de34-4487-bd5f-239ee6b50ff6", "0dbfbf92-0412-45e4-b517-538c3c5618ea"],
      "maxCapacity": 24,
      "minCapacity": 12,
      "memberOnly": true,
      "priceMember": 60
    }'

  5. Clinic - good

 curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "Serve and Return Clinic",
      "eventType": "clinic",
      "description": "Improve your serve and return game with professional instruction",
      "startTime": "2025-10-22T10:00:00-04:00",
      "endTime": "2025-10-22T12:00:00-04:00",
      "courtIds": ["619c6532-bd9f-402c-aa15-e67b84e321b6"],
      "maxCapacity": 12,
      "minCapacity": 4,
      "skillLevels": ["3.0", "3.5", "4.0"],
      "priceMember": 40,
      "priceGuest": 55,
      "equipmentProvided": false,
      "specialInstructions": "This will be indoor and outdoor so please come prepared to be out in the sun!"
    }'

  6. Private Lesson - good 

  curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "Private Coaching Session",
      "eventType": "private_lesson",
      "description": "One-on-one personalized coaching",
      "startTime": "2025-10-18T15:00:00-04:00",
      "endTime": "2025-10-18T16:00:00-04:00",
      "courtIds": ["76d66b4c-512a-44ab-b41d-27932a9a1157"],
      "maxCapacity": 2,
      "minCapacity": 1,
      "priceMember": 75,
      "priceGuest": 90,
      "memberOnly": false
    }'

  7. Multi-Day Event - good

  curl -X POST http://localhost:3002/api/events \
    -H 'Content-Type: application/json' \
    -d '{
      "title": "Weekend Pickleball Bootcamp",
      "eventType": "clinic",
      "description": "Intensive 2-day training program for serious players",
      "startTime": "2025-12-08T08:00:00-05:00",
      "endTime": "2025-12-09T17:00:00-05:00",
      "courtIds": ["e2123a79-7ea7-41e6-a5ea-ea2282118d9b", "20777d3c-8a4c-4501-bc53-21e5b377d7eb", "03a3906c-50dd-4ceb-9e8d-3ccdb5245f47", "76d66b4c-512a-44ab-b41d-27932a9a1157"],
      "maxCapacity": 32,
      "minCapacity": 16,
      "skillLevels": ["3.5", "4.0", "4.5"],
      "priceMember": 250,
      "priceGuest": 325,
      "equipmentProvided": true,
      "specialInstructions": "Lunch provided both days. Bring multiple paddles and athletic wear."
    }'


  Additional Useful Commands:

  Get All Events

  curl http://localhost:3002/api/events | jq

  Get Events by Date Range

  curl "http://localhost:3002/api/events?start=2025-10-01&end=2025-10-31" | jq

  Get Events by Type

  curl "http://localhost:3002/api/events?eventType=clinic" | jq

  Get Specific Event Details

  curl http://localhost:3002/api/events/95d96088-6b46-4497-baae-9a7ffa67fd2f | jq

  Register for an Event

  curl -X POST http://localhost:3002/api/events/95d96088-6b46-4497-baae-9a7ffa67fd2f/register
   \
    -H 'Content-Type: application/json' \
    -d '{
      "playerName": "John Doe",
      "playerEmail": "john@example.com",
      "playerPhone": "555-1234",
      "skillLevel": "intermediate",
      "duprRating": 3.5,
      "notes": "First time at this venue"
    }' | jq

  Get Available Event Types

  curl http://localhost:3002/api/events/meta/types | jq

  Get DUPR Brackets

  curl http://localhost:3002/api/events/meta/dupr-brackets | jq

  Get All Courts

  curl http://localhost:3002/api/courts | jq

  All these commands work with your API running on port 3002. Remember to use valid court IDs
   from your database when creating events!