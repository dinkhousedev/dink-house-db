# Spectator Features & Public Interface

## Overview

The spectator experience provides friends, family, and fans with real-time tournament access through web and mobile interfaces. This system enables remote viewing, on-site navigation, and engagement features without requiring authentication.

## Public Tournament Portal

### Landing Page

```javascript
class PublicTournamentView {
  renderLanding() {
    return {
      hero: {
        tournamentName: 'Summer Championships 2024',
        status: 'LIVE NOW',
        venue: 'Dink House Main',
        currentRound: 'Quarterfinals'
      },

      quickStats: {
        totalMatches: 168,
        completed: 92,
        inProgress: 8,
        courtsActive: '6 of 8'
      },

      featured: {
        match: {
          court: 'Center Court',
          division: "Men's Open",
          teams: ['Smith/Jones', 'Wilson/Davis'],
          score: '11-9, 8-11, 5-3',
          stream: 'LIVE'
        }
      },

      navigation: [
        'Live Scores',
        'Brackets',
        'Schedule',
        'Players',
        'Venue Info',
        'Stream'
      ]
    };
  }
}
```

### Live Scoring Dashboard

```html
<LiveScoringDashboard>
  <FilterBar>
    <DivisionFilter>
      <Option>All Divisions</Option>
      <Option>Men's 3.5</Option>
      <Option>Women's 4.0</Option>
    </DivisionFilter>

    <CourtFilter>
      <Option>All Courts</Option>
      <Option>Center Court</Option>
      <Option>Courts 1-4</Option>
    </CourtFilter>

    <StatusFilter>
      <Option>In Progress</Option>
      <Option>Upcoming</Option>
      <Option>Completed</Option>
    </StatusFilter>
  </FilterBar>

  <LiveMatchGrid>
    <MatchCard status="live">
      <Court>Court 1</Court>
      <Division>MD 3.5</Division>
      <Teams>
        <Team1 serving>Johnson/Smith - 11, 8, 5</Team1>
        <Team2>Davis/Wilson - 9, 11, 3</Team2>
      </Teams>
      <Duration>23:45</Duration>
      <WatchButton />
    </MatchCard>
  </LiveMatchGrid>

  <AutoRefresh interval="10s" />
</LiveScoringDashboard>
```

## Interactive Bracket Viewer

### Bracket Interface

```javascript
class BracketViewer {
  constructor(divisionId) {
    this.divisionId = divisionId;
    this.zoomLevel = 1;
    this.selectedMatch = null;
  }

  renderBracket() {
    return (
      <BracketContainer>
        <BracketControls>
          <ZoomIn />
          <ZoomOut />
          <FitToScreen />
          <FullScreen />
          <PrintBracket />
          <ShareBracket />
        </BracketControls>

        <InteractiveBracket>
          {this.rounds.map(round => (
            <Round>
              <RoundHeader>{round.name}</RoundHeader>
              {round.matches.map(match => (
                <MatchNode
                  onClick={() => this.showMatchDetails(match)}
                  status={match.status}
                  highlighted={this.isTracking(match)}
                >
                  <Team1>{match.team1}</Team1>
                  <Score>{match.score}</Score>
                  <Team2>{match.team2}</Team2>
                </MatchNode>
              ))}
            </Round>
          ))}
        </InteractiveBracket>

        <BracketLegend>
          <Status color="green">Completed</Status>
          <Status color="yellow">In Progress</Status>
          <Status color="gray">Upcoming</Status>
          <Status color="red">Live on Court</Status>
        </BracketLegend>
      </BracketContainer>
    );
  }

  showMatchDetails(match) {
    return {
      matchNumber: match.number,
      round: match.round,
      court: match.court,
      scheduledTime: match.time,
      actualStart: match.startTime,
      duration: match.duration,

      teams: {
        team1: this.getTeamDetails(match.team1Id),
        team2: this.getTeamDetails(match.team2Id)
      },

      scores: match.games,

      progression: {
        winnerTo: match.winnerToMatch,
        loserTo: match.loserToMatch
      },

      stats: {
        longestRally: match.stats?.longestRally,
        totalPoints: match.stats?.totalPoints,
        comebacks: match.stats?.comebacks
      }
    };
  }
}
```

## Player Profiles & Tracking

### Player Search & Discovery

```javascript
class PlayerDirectory {
  searchPlayers(query) {
    return {
      filters: {
        name: query,
        division: null,
        rating: null,
        hometown: null
      },

      results: [
        {
          id: 'player123',
          name: 'John Smith',
          photo: 'url',
          rating: { dupr: 3.75, trend: '↑' },
          division: 'Men\'s 3.5',
          partner: 'Mike Johnson',
          hometown: 'Austin, TX',
          seed: 4
        }
      ]
    };
  }

  renderPlayerProfile(playerId) {
    return (
      <PlayerProfile>
        <Header>
          <Photo src={player.photo} />
          <Name>{player.name}</Name>
          <Rating>DUPR: {player.rating}</Rating>
          <Division>{player.division}</Division>
        </Header>

        <TournamentProgress>
          <Status>Active - Quarterfinals</Status>
          <Record>W: 3 | L: 0</Record>
          <NextMatch>
            <Time>2:30 PM (est)</Time>
            <Court>Court 4</Court>
            <Opponent>Wilson/Davis</Opponent>
          </NextMatch>
        </TournamentProgress>

        <MatchHistory>
          <Match>
            <Round>R16</Round>
            <Result>W 11-4, 11-7</Result>
            <Duration>22 min</Duration>
          </Match>
        </MatchHistory>

        <Actions>
          <FollowPlayer />
          <NotifyMatches />
          <ViewPartner />
        </Actions>
      </PlayerProfile>
    );
  }
}
```

### Player Tracking

```javascript
class PlayerTracker {
  trackPlayer(playerId) {
    // Add player to tracking list
    this.trackedPlayers.add(playerId);

    // Subscribe to updates
    this.subscribeToPlayer(playerId, updates => {
      this.notify({
        type: updates.type,
        message: `${updates.playerName} ${updates.action}`,
        link: updates.matchLink
      });
    });

    // Highlight in brackets
    this.highlightPlayerMatches(playerId);
  }

  getTrackedPlayersDashboard() {
    return (
      <TrackedPlayers>
        {this.trackedPlayers.map(player => (
          <PlayerCard>
            <Name>{player.name}</Name>
            <Status>{player.currentStatus}</Status>
            <NextMatch>{player.nextMatch}</NextMatch>
            <LiveIndicator show={player.isPlaying} />
            <UntrackButton />
          </PlayerCard>
        ))}
      </TrackedPlayers>
    );
  }
}
```

## Venue Navigation

### Interactive Venue Map

```javascript
class VenueMap {
  constructor(venueId) {
    this.venue = this.loadVenue(venueId);
    this.userLocation = null;
  }

  renderMap() {
    return (
      <VenueMapContainer>
        <MapControls>
          <LayerToggle>
            <Layer name="Courts" active />
            <Layer name="Facilities" active />
            <Layer name="Food & Drink" active />
            <Layer name="Parking" />
          </LayerToggle>

          <SearchBox placeholder="Find court, restroom, food..." />
        </MapControls>

        <InteractiveMap>
          <Courts>
            {this.venue.courts.map(court => (
              <Court
                number={court.number}
                status={court.currentMatch ? 'active' : 'free'}
                onClick={() => this.showCourtInfo(court)}
              />
            ))}
          </Courts>

          <Facilities>
            <Restrooms locations={this.venue.restrooms} />
            <Medical location={this.venue.medical} />
            <Registration location={this.venue.registration} />
          </Facilities>

          <Amenities>
            <FoodVendors locations={this.venue.food} />
            <ProShop location={this.venue.proShop} />
            <Seating areas={this.venue.seating} />
          </Amenities>
        </InteractiveMap>

        <Navigation show={this.navigationActive}>
          <Route from={this.userLocation} to={this.destination} />
          <Distance>{this.calculateDistance()} yards</Distance>
          <Time>{this.estimateWalkTime()} min walk</Time>
        </Navigation>
      </VenueMapContainer>
    );
  }
}
```

## Live Streaming Integration

### Stream Viewer

```javascript
class StreamViewer {
  constructor() {
    this.streams = this.getAvailableStreams();
    this.quality = 'auto';
  }

  renderStreamInterface() {
    return (
      <StreamContainer>
        <StreamSelector>
          <Select>
            <Option>Center Court - Finals</Option>
            <Option>Court 1 - Semifinals</Option>
            <Option>Multi-Court View</Option>
          </Select>
        </StreamSelector>

        <VideoPlayer>
          <Video src={this.currentStream} />
          <Controls>
            <PlayPause />
            <Volume />
            <Quality options={['auto', '1080p', '720p', '480p']} />
            <FullScreen />
            <PictureInPicture />
          </Controls>
        </VideoPlayer>

        <StreamInfo>
          <MatchDetails>
            <Division>Men's Open Finals</Division>
            <Teams>Smith/Jones vs Wilson/Davis</Teams>
            <Score live>11-9, 8-11, 5-3</Score>
          </MatchDetails>

          <ViewerCount>327 watching</ViewerCount>
        </StreamInfo>

        <StreamChat authenticated={false}>
          <ReadOnlyChat messages={this.chatMessages} />
          <LoginPrompt>Sign in to chat</LoginPrompt>
        </StreamChat>
      </StreamContainer>
    );
  }
}
```

## Social Media Integration

### Social Feed

```javascript
class TournamentSocialFeed {
  constructor(tournamentHashtag) {
    this.hashtag = tournamentHashtag;
    this.platforms = ['twitter', 'instagram', 'facebook'];
  }

  renderSocialWall() {
    return (
      <SocialWall>
        <Header>
          <Title>#{this.hashtag}</Title>
          <Platforms>
            {this.platforms.map(p => <Icon platform={p} />)}
          </Platforms>
        </Header>

        <PostGrid>
          <Post platform="twitter">
            <Author>@pickleballfan</Author>
            <Content>Amazing rally in the semifinals! 🎾</Content>
            <Media type="video" src="..." />
            <Timestamp>2 min ago</Timestamp>
          </Post>

          <Post platform="instagram">
            <Author>dinkhouse_official</Author>
            <Content>Championship Sunday vibes ☀️</Content>
            <Media type="image" src="..." />
            <Likes>234</Likes>
          </Post>
        </PostGrid>

        <PostButton>
          Share your experience #SummerChampionships2024
        </PostButton>
      </SocialWall>
    );
  }
}
```

## Schedule & Results

### Tournament Schedule View

```javascript
class ScheduleViewer {
  renderSchedule(date) {
    return (
      <ScheduleContainer>
        <DateSelector>
          <Day>Saturday</Day>
          <Day active>Sunday</Day>
        </DateSelector>

        <TimelineView>
          <TimeSlot time="8:00 AM">
            <Event type="ceremony">Opening Ceremony</Event>
            <Event type="matches">
              Round of 32 - All Divisions
              <Courts>Courts 1-8</Courts>
            </Event>
          </TimeSlot>

          <TimeSlot time="10:00 AM">
            <Event type="matches" highlight>
              Round of 16 - Men's Open
              <Courts>Center Court</Courts>
              <Stream available />
            </Event>
          </TimeSlot>

          <TimeSlot time="2:00 PM">
            <Event type="special">
              Skills Challenge
              <Location>Court 4</Location>
            </Event>
          </TimeSlot>

          <CurrentTime>
            <Indicator />
            <Label>NOW - 11:32 AM</Label>
          </CurrentTime>
        </TimelineView>

        <UpcomingHighlights>
          <Highlight>
            <Time>2:00 PM</Time>
            <Event>Men's Open Semifinals</Event>
          </Highlight>
          <Highlight>
            <Time>4:00 PM</Time>
            <Event>Women's 4.0 Finals</Event>
          </Highlight>
        </UpcomingHighlights>
      </ScheduleContainer>
    );
  }
}
```

## Analytics & Statistics

### Tournament Statistics Dashboard

```javascript
class TournamentStats {
  renderStatsDashboard() {
    return (
      <StatsContainer>
        <OverallStats>
          <Stat>
            <Label>Total Matches</Label>
            <Value>168</Value>
          </Stat>
          <Stat>
            <Label>Average Duration</Label>
            <Value>32 min</Value>
          </Stat>
          <Stat>
            <Label>Longest Match</Label>
            <Value>67 min</Value>
          </Stat>
          <Stat>
            <Label>Total Points</Label>
            <Value>4,892</Value>
          </Stat>
        </OverallStats>

        <Leaderboards>
          <Category title="Fastest Matches">
            <Entry>Smith/Jones - 18 min</Entry>
            <Entry>Davis/Wilson - 19 min</Entry>
          </Category>

          <Category title="Biggest Comebacks">
            <Entry>Team Alpha - from 2-9 to 11-9</Entry>
          </Category>

          <Category title="Most Aces">
            <Entry>Johnson - 12 aces</Entry>
          </Category>
        </Leaderboards>

        <DivisionBreakdown>
          <Chart type="bar">
            {/* Matches per division */}
          </Chart>
        </DivisionBreakdown>

        <TrendingMatches>
          <Match trending>
            <Reason>Upset Alert</Reason>
            <Details>#8 seed leading #1 seed</Details>
          </Match>
        </TrendingMatches>
      </StatsContainer>
    );
  }
}
```

## Mobile Web Experience

### Progressive Web App Features

```javascript
const spectatorPWA = {
  features: {
    installable: true,
    offline: {
      brackets: true,
      schedule: true,
      venueMap: true,
      cachedScores: true
    },

    pushNotifications: {
      matchStart: 'Tracked player starting',
      matchEnd: 'Match completed',
      upsetAlert: 'Major upset happening',
      streamAvailable: 'Live stream started'
    },

    homeScreen: {
      icon: true,
      splashScreen: true,
      fullScreen: false
    }
  },

  performance: {
    lazyLoading: true,
    imageOptimization: true,
    codeSpitting: true,
    caching: 'service-worker'
  }
};
```

## Accessibility Features

### Inclusive Spectator Experience

```javascript
class AccessibleSpectator {
  features = {
    visual: {
      screenReader: {
        ariaLabels: true,
        liveRegions: true,
        skipLinks: true
      },

      contrast: {
        highContrast: true,
        darkMode: true,
        fontSize: ['normal', 'large', 'xlarge']
      },

      alternatives: {
        audioCommentary: true,
        textDescriptions: true
      }
    },

    motor: {
      keyboardNavigation: true,
      focusIndicators: true,
      largeClickTargets: true,
      reducedMotion: true
    },

    cognitive: {
      simpleLanguage: true,
      clearNavigation: true,
      consistentLayout: true,
      errorGuidance: true
    }
  };
}
```

## Sponsor Integration

### Sponsor Visibility

```javascript
class SponsorDisplay {
  renderSponsorContent() {
    return {
      banner: {
        position: 'top',
        rotation: this.sponsors,
        duration: 10000
      },

      courtSponsors: {
        display: 'court-name',
        example: 'Acme Sports Court 1'
      },

      matchSponsors: {
        display: 'pre-match',
        message: 'This match brought to you by...'
      },

      interactive: {
        contests: true,
        polls: true,
        giveaways: true
      }
    };
  }
}
```

## Emergency Information

### Public Safety Features

```javascript
class PublicSafety {
  renderEmergencyInfo() {
    return (
      <EmergencyPanel>
        <QuickContacts>
          <Emergency>911</Emergency>
          <Security>Security: (555) 100-2000</Security>
          <Medical>Medical Tent: Court 4</Medical>
        </QuickContacts>

        <WeatherAlerts>
          <Alert level="watch">
            <Type>Lightning</Type>
            <Time>Possible at 3 PM</Time>
            <Action>Monitor announcements</Action>
          </Alert>
        </WeatherAlerts>

        <EvacuationMap>
          <ExitRoutes />
          <AssemblyPoints />
          <CurrentLocation />
        </EvacuationMap>

        <Announcements>
          <PA>Live PA system updates</PA>
          <Push>Enable notifications</Push>
        </Announcements>
      </EmergencyPanel>
    );
  }
}
```

## Performance Metrics

### Spectator Engagement KPIs

1. **Page Views**: Track popular sections
2. **Session Duration**: Average time on site
3. **Live Score Refresh Rate**: Real-time engagement
4. **Stream Viewership**: Concurrent viewers
5. **Social Shares**: Viral reach
6. **Mobile vs Desktop**: Platform preferences
7. **Feature Usage**: Most used tools
8. **Return Visitors**: Engagement retention