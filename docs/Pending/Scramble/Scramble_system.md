# Pickleball Scramble: Complete System Flow

## 1. Event Creation (Staff)

### Staff Actions:
1. **Create Event**
   - Log into staff dashboard
   - Click "New Scramble Event"
   - Fill in event details:
     - Event name and description
     - Date, time, and duration
     - Scramble type (DUPR rated, social, beginner)
     - Max players
     - Price per player
     - Registration deadline
   - Set up notification preferences:
     - When to send reminders
     - What information to include

### System Actions:
- Creates new event in `events` table
- Generates unique event page
- Sets up payment processing
- Initializes real-time event channel

## 2. Player Notification

### System Actions:
1. **Initial Notification**
   - Sends push notification to all app users who opted in
   - Creates in-app notification
   - Sends email announcement (if configured)

2. **Notification Content**:
   - Event name and type
   - Date, time, location
   - Price and registration deadline
   - "Sign Up" button

## 3. Player Registration

### Player Actions:
1. **View Event**
   - Clicks notification or browses events
   - Views event details
   - Checks available spots

2. **Register & Pay**
   - Clicks "Register"
   - If DUPR event: System verifies DUPR account
   - Enters payment info
   - Confirms registration

### System Actions:
- Creates entry in `event_registrations`
- Processes payment via Stripe
- Updates event availability
- Sends confirmation (app + email)
- Adds to player's event calendar

## 4. Pre-Event

### System Actions:
1. **Reminders**
   - 48-hour reminder
   - 2-hour reminder
   - Includes:
     - Event time
     - What to bring
     - Location/parking info

2. **Check-in Opens**
   - 30 minutes before start
   - Players can check in via app
   - Staff can check in players

## 5. Event Day - Check-in

### Staff Actions:
- Open check-in
- Verify player identities
- Handle walk-ins (if space available)
- Mark no-shows

### System Actions:
- Updates player status to "checked in"
- Tracks check-in time
- Updates real-time player list
- Adjusts teams if needed

## 6. Scramble Setup

### System Actions:
1. **Initial Pairing**
   - Groups players by skill level
   - Creates initial random pairings
   - Ensures no previous partnerships
   - Balances teams

2. **Court Assignment**
   - Assigns matches to courts
   - Displays on court monitors
   - Sends to player devices

## 7. Game Play

### Round Flow (Repeats for each round):
1. **Round Start**
   - System announces round start
   - Displays court assignments
   - Starts round timer

2. **During Play**
   - Staff updates scores
   - Players can view live standings
   - System tracks match progress

3. **Round End**
   - Staff confirms final scores
   - System records results
   - Updates player statistics
   - Calculates new pairings

### System Handles:
- Score validation
- Time management
- Fair rotation
- Leaderboard updates

## 8. Between Rounds

### System Actions:
1. **Generate New Pairings**
   - Considers:
     - Previous partners
     - Skill balance
     - Court assignments
     - Player preferences

2. **Notify Players**
   - New court assignments
   - Next round start time
   - Current standings

## 9. Event Conclusion

### System Actions:
1. **Final Calculations**
   - Calculates winners
   - Updates DUPR ratings (if applicable)
   - Generates event summary

2. **Notifications**
   - Sends results to all participants
   - Includes:
     - Final standings
     - Personal statistics
     - Next event information

3. **Follow-up**
   - Feedback survey
   - Photo gallery link
   - Social sharing options

## 10. Post-Event

### System Actions:
1. **Data Processing**
   - Updates player profiles
   - Adjusts DUPR ratings
   - Processes any refunds

2. **Analytics**
   - Generates event report
   - Tracks player engagement
   - Identifies popular time slots

## Database Flow

### Key Tables:
1. `events` - Event details
2. `players` - Player information
3. `event_registrations` - Links players to events
4. `matches` - Individual games
5. `player_matches` - Links players to matches
6. `rounds` - Round information
7. `payments` - Payment records

### Real-time Updates:
- Player check-ins
- Match scores
- Court assignments
- Leaderboard changes

## User Experience Highlights

### For Players:
- Simple, clear interface
- Real-time updates
- Easy check-in
- Live standings

### For Staff:
- Intuitive dashboard
- Quick score entry
- Player management
- Real-time monitoring

### For Organizers:
- Comprehensive reporting
- Financial tracking
- Player engagement metrics
- Event performance analysis

This flow ensures a smooth, engaging experience for all participants while providing staff with the tools they need to manage events efficiently. The system handles the complexity behind the scenes, allowing everyone to focus on enjoying the game.