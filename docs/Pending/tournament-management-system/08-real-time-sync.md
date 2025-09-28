# Real-Time Synchronization Architecture

## Overview

The real-time synchronization system ensures all tournament participants receive instant updates across all devices and interfaces. This document details the WebSocket architecture, event handling, conflict resolution, and optimization strategies for maintaining synchronized state across thousands of concurrent users.

## Architecture Overview

### Technology Stack

```javascript
const realtimeStack = {
  primary: {
    websocket: 'Supabase Realtime',
    fallback: 'Socket.io',
    protocol: 'WebSocket with HTTP fallback'
  },

  infrastructure: {
    loadBalancer: 'NGINX with sticky sessions',
    messageQueue: 'Redis Pub/Sub',
    stateStore: 'Redis with persistence',
    database: 'PostgreSQL with LISTEN/NOTIFY'
  },

  scaling: {
    horizontal: 'Multiple WebSocket servers',
    vertical: 'Auto-scaling based on connections',
    regions: 'Multi-region deployment'
  }
};
```

### System Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     Client Applications                   │
│  (Web App, Mobile App, Staff App, Public View)           │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│                    Load Balancer (NGINX)                  │
│                    (Sticky Sessions)                      │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│              WebSocket Server Cluster                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   WS Node 1 │  │   WS Node 2 │  │   WS Node 3 │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│                    Redis Pub/Sub Layer                    │
│              (Message Broadcasting & State)               │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│                  PostgreSQL Database                      │
│              (Source of Truth + LISTEN/NOTIFY)            │
└──────────────────────────────────────────────────────────┘
```

## WebSocket Connection Management

### Connection Lifecycle

```javascript
class WebSocketConnection {
  constructor(userId, role) {
    this.userId = userId;
    this.role = role;
    this.connectionId = generateId();
    this.subscriptions = new Set();
    this.heartbeat = null;
  }

  async connect() {
    try {
      // Establish WebSocket connection
      this.socket = new WebSocket(this.getEndpoint());

      // Authentication
      await this.authenticate();

      // Setup event handlers
      this.setupEventHandlers();

      // Start heartbeat
      this.startHeartbeat();

      // Subscribe to default channels
      await this.subscribeToDefaults();

      return {
        status: 'connected',
        connectionId: this.connectionId,
        latency: await this.measureLatency()
      };
    } catch (error) {
      return this.handleConnectionError(error);
    }
  }

  setupEventHandlers() {
    this.socket.on('message', this.handleMessage.bind(this));
    this.socket.on('error', this.handleError.bind(this));
    this.socket.on('close', this.handleDisconnect.bind(this));
    this.socket.on('reconnect', this.handleReconnect.bind(this));
  }

  startHeartbeat() {
    this.heartbeat = setInterval(() => {
      this.socket.send(JSON.stringify({
        type: 'ping',
        timestamp: Date.now()
      }));
    }, 30000); // 30 seconds
  }

  async handleDisconnect() {
    clearInterval(this.heartbeat);

    // Store state for reconnection
    await this.saveConnectionState();

    // Attempt reconnection with exponential backoff
    this.reconnectWithBackoff();
  }

  reconnectWithBackoff(attempt = 1) {
    const delay = Math.min(1000 * Math.pow(2, attempt), 30000);

    setTimeout(async () => {
      try {
        await this.connect();
        await this.restoreConnectionState();
      } catch {
        this.reconnectWithBackoff(attempt + 1);
      }
    }, delay);
  }
}
```

### Channel Subscription Management

```javascript
class ChannelManager {
  constructor(connection) {
    this.connection = connection;
    this.channels = new Map();
  }

  async subscribe(channel, options = {}) {
    // Check permissions
    if (!this.hasPermission(channel)) {
      throw new Error('Insufficient permissions');
    }

    // Create subscription
    const subscription = {
      channel: channel,
      filters: options.filters || {},
      handlers: options.handlers || {},
      priority: options.priority || 'normal'
    };

    // Register with server
    await this.connection.send({
      type: 'subscribe',
      channel: channel,
      subscription: subscription
    });

    // Store locally
    this.channels.set(channel, subscription);

    return subscription;
  }

  getAvailableChannels(tournamentId) {
    return {
      global: [
        `tournament:${tournamentId}:announcements`,
        `tournament:${tournamentId}:scores`,
        `tournament:${tournamentId}:brackets`
      ],

      authenticated: [
        `tournament:${tournamentId}:teams`,
        `tournament:${tournamentId}:schedule`,
        `user:${this.userId}:notifications`
      ],

      staff: [
        `tournament:${tournamentId}:staff`,
        `tournament:${tournamentId}:operations`,
        `tournament:${tournamentId}:emergency`
      ],

      director: [
        `tournament:${tournamentId}:admin`,
        `tournament:${tournamentId}:financial`,
        `tournament:${tournamentId}:analytics`
      ]
    };
  }
}
```

## Event Broadcasting System

### Event Types and Priorities

```javascript
const eventTypes = {
  // Critical Priority (Immediate delivery)
  critical: {
    emergency: 'tournament:emergency',
    weatherAlert: 'tournament:weather:alert',
    evacuation: 'tournament:evacuation',
    medicalEmergency: 'tournament:medical:emergency'
  },

  // High Priority (< 100ms delivery)
  high: {
    scoreUpdate: 'match:score:update',
    matchStart: 'match:start',
    matchComplete: 'match:complete',
    bracketUpdate: 'bracket:update',
    courtAssignment: 'court:assignment'
  },

  // Normal Priority (< 500ms delivery)
  normal: {
    registration: 'team:registration',
    checkIn: 'team:checkin',
    scheduleChange: 'schedule:change',
    announcement: 'tournament:announcement'
  },

  // Low Priority (< 2000ms delivery)
  low: {
    statistics: 'tournament:stats',
    socialUpdate: 'social:update',
    sponsorContent: 'sponsor:content'
  }
};
```

### Event Broadcasting

```javascript
class EventBroadcaster {
  constructor(redis, postgresql) {
    this.redis = redis;
    this.db = postgresql;
    this.messageQueue = [];
  }

  async broadcast(event) {
    // Validate event
    const validated = this.validateEvent(event);

    // Store in database
    await this.persistEvent(validated);

    // Determine recipients
    const recipients = await this.getRecipients(validated);

    // Queue for delivery
    const message = {
      id: generateId(),
      event: validated,
      recipients: recipients,
      priority: this.getPriority(validated.type),
      timestamp: Date.now()
    };

    // Broadcast based on priority
    if (message.priority === 'critical') {
      await this.broadcastImmediate(message);
    } else {
      await this.queueBroadcast(message);
    }

    return message.id;
  }

  async broadcastImmediate(message) {
    // Use Redis pub/sub for immediate delivery
    await this.redis.publish(message.event.channel, JSON.stringify({
      ...message,
      broadcast_type: 'immediate'
    }));

    // Also send via WebSocket for connected clients
    this.sendToConnectedClients(message);
  }

  async queueBroadcast(message) {
    // Add to priority queue
    this.messageQueue.push(message);

    // Sort by priority
    this.messageQueue.sort((a, b) =>
      this.priorityWeight(a.priority) - this.priorityWeight(b.priority)
    );

    // Process queue
    this.processQueue();
  }

  async processQueue() {
    while (this.messageQueue.length > 0) {
      const batch = this.messageQueue.splice(0, 100); // Process 100 at a time

      await Promise.all(batch.map(message =>
        this.redis.publish(message.event.channel, JSON.stringify(message))
      ));

      // Rate limiting
      await this.delay(10);
    }
  }
}
```

## State Synchronization

### Optimistic Updates

```javascript
class OptimisticUpdates {
  constructor() {
    this.pendingUpdates = new Map();
    this.confirmed = new Map();
  }

  async applyOptimisticUpdate(update) {
    // Generate temporary ID
    const tempId = `temp_${generateId()}`;

    // Apply update to local state immediately
    this.applyToLocalState(update, tempId);

    // Store pending update
    this.pendingUpdates.set(tempId, {
      update: update,
      timestamp: Date.now(),
      attempts: 0
    });

    // Send to server
    try {
      const result = await this.sendToServer(update);

      // Replace temp ID with real ID
      this.confirmUpdate(tempId, result.id);

      return result;
    } catch (error) {
      // Revert on failure
      this.revertUpdate(tempId);
      throw error;
    }
  }

  confirmUpdate(tempId, realId) {
    const pending = this.pendingUpdates.get(tempId);
    if (pending) {
      this.confirmed.set(realId, pending.update);
      this.pendingUpdates.delete(tempId);
      this.updateLocalReferences(tempId, realId);
    }
  }

  revertUpdate(tempId) {
    const pending = this.pendingUpdates.get(tempId);
    if (pending) {
      this.removeFromLocalState(pending.update, tempId);
      this.pendingUpdates.delete(tempId);
      this.notifyUser('Update failed and was reverted');
    }
  }
}
```

### Conflict Resolution

```javascript
class ConflictResolver {
  constructor() {
    this.strategies = {
      lastWrite: this.lastWriteWins,
      merge: this.mergeChanges,
      manual: this.requireManualResolution,
      operational: this.operationalTransform
    };
  }

  async resolveConflict(local, remote, context) {
    // Determine conflict type
    const conflictType = this.analyzeConflict(local, remote);

    // Select resolution strategy
    const strategy = this.selectStrategy(conflictType, context);

    // Apply resolution
    const resolved = await strategy(local, remote, context);

    // Validate resolution
    if (!this.isValid(resolved)) {
      return this.requireManualResolution(local, remote, context);
    }

    return resolved;
  }

  lastWriteWins(local, remote) {
    // Compare timestamps
    return local.timestamp > remote.timestamp ? local : remote;
  }

  mergeChanges(local, remote) {
    // Three-way merge
    const base = this.getCommonAncestor(local, remote);
    const merged = {};

    // Merge non-conflicting changes
    Object.keys({...local, ...remote}).forEach(key => {
      if (local[key] === remote[key]) {
        merged[key] = local[key];
      } else if (local[key] === base[key]) {
        merged[key] = remote[key];
      } else if (remote[key] === base[key]) {
        merged[key] = local[key];
      } else {
        // Both changed - need resolution
        merged[key] = this.resolveFieldConflict(
          key,
          local[key],
          remote[key]
        );
      }
    });

    return merged;
  }

  operationalTransform(local, remote, context) {
    // Transform operations to be commutative
    const transformedLocal = this.transform(local, remote, 'left');
    const transformedRemote = this.transform(remote, local, 'right');

    // Apply both transformations
    return this.applyOperations([transformedLocal, transformedRemote]);
  }
}
```

## Real-Time Score Updates

### Score Synchronization System

```javascript
class ScoreSyncSystem {
  constructor(matchId) {
    this.matchId = matchId;
    this.localScore = null;
    this.remoteScore = null;
    this.syncBuffer = [];
  }

  async updateScore(update) {
    // Validate score update
    if (!this.isValidScoreUpdate(update)) {
      throw new Error('Invalid score update');
    }

    // Apply optimistically
    this.applyLocalUpdate(update);

    // Buffer for batch processing
    this.syncBuffer.push(update);

    // Debounce sync (wait for rapid updates)
    this.debouncedSync();
  }

  debouncedSync = debounce(async () => {
    if (this.syncBuffer.length === 0) return;

    // Batch updates
    const batch = this.syncBuffer.splice(0, this.syncBuffer.length);

    try {
      // Send batch to server
      const result = await this.sendBatch(batch);

      // Update confirmed state
      this.remoteScore = result.score;

      // Broadcast to subscribers
      this.broadcastScoreUpdate(result);
    } catch (error) {
      // Rollback on failure
      this.rollbackBatch(batch);
      throw error;
    }
  }, 500); // 500ms debounce

  broadcastScoreUpdate(score) {
    const event = {
      type: 'score:update',
      matchId: this.matchId,
      score: score,
      timestamp: Date.now()
    };

    // Send to different channels
    this.broadcast('match:' + this.matchId, event);
    this.broadcast('division:' + score.divisionId, event);
    this.broadcast('tournament:scores', event);
  }
}
```

## Presence System

### User Presence Tracking

```javascript
class PresenceSystem {
  constructor() {
    this.presence = new Map();
    this.heartbeatInterval = 30000; // 30 seconds
  }

  async trackPresence(userId, context) {
    const presenceData = {
      userId: userId,
      status: 'online',
      location: context.location, // e.g., 'match:123', 'bracket:div1'
      device: context.device,
      lastSeen: Date.now()
    };

    // Store in Redis with TTL
    await this.redis.setex(
      `presence:${userId}`,
      60, // 60 seconds TTL
      JSON.stringify(presenceData)
    );

    // Broadcast presence update
    this.broadcastPresence(presenceData);

    return presenceData;
  }

  async getPresence(scope) {
    switch(scope.type) {
      case 'match':
        return this.getMatchViewers(scope.matchId);
      case 'tournament':
        return this.getTournamentPresence(scope.tournamentId);
      case 'division':
        return this.getDivisionPresence(scope.divisionId);
    }
  }

  async getMatchViewers(matchId) {
    const viewers = await this.redis.smembers(`viewing:match:${matchId}`);

    return Promise.all(viewers.map(async viewer => {
      const presence = await this.redis.get(`presence:${viewer}`);
      return JSON.parse(presence);
    }));
  }

  renderPresenceIndicators() {
    return (
      <PresenceBar>
        <ViewerCount>
          <Icon>👥</Icon>
          <Count>{this.viewerCount} watching</Count>
        </ViewerCount>

        <ActiveUsers>
          {this.getActiveUsers().map(user => (
            <Avatar
              user={user}
              status={user.status}
              tooltip={`${user.name} - ${user.location}`}
            />
          ))}
        </ActiveUsers>

        <LiveIndicator pulse={true}>
          LIVE
        </LiveIndicator>
      </PresenceBar>
    );
  }
}
```

## Offline Support & Sync

### Offline Queue Management

```javascript
class OfflineSync {
  constructor() {
    this.offlineQueue = [];
    this.syncInProgress = false;
  }

  async queueOfflineAction(action) {
    // Add to IndexedDB queue
    await this.db.offlineQueue.add({
      id: generateId(),
      action: action,
      timestamp: Date.now(),
      attempts: 0
    });

    // Attempt sync if online
    if (navigator.onLine) {
      this.attemptSync();
    }
  }

  async attemptSync() {
    if (this.syncInProgress) return;
    this.syncInProgress = true;

    try {
      // Get pending actions
      const pending = await this.db.offlineQueue
        .orderBy('timestamp')
        .toArray();

      for (const item of pending) {
        try {
          // Process action
          await this.processOfflineAction(item.action);

          // Remove from queue
          await this.db.offlineQueue.delete(item.id);
        } catch (error) {
          // Increment attempts
          item.attempts++;

          if (item.attempts >= 3) {
            // Move to failed queue
            await this.moveToFailed(item);
          } else {
            // Update attempt count
            await this.db.offlineQueue.update(item.id, {
              attempts: item.attempts
            });
          }
        }
      }
    } finally {
      this.syncInProgress = false;
    }
  }

  setupAutoSync() {
    // Sync on reconnect
    window.addEventListener('online', () => {
      this.attemptSync();
    });

    // Periodic sync attempt
    setInterval(() => {
      if (navigator.onLine) {
        this.attemptSync();
      }
    }, 30000); // Every 30 seconds
  }
}
```

## Performance Optimization

### Message Batching and Compression

```javascript
class MessageOptimizer {
  constructor() {
    this.batchSize = 50;
    this.compressionThreshold = 1024; // 1KB
  }

  async optimizeMessage(message) {
    // Compress if large
    if (JSON.stringify(message).length > this.compressionThreshold) {
      message = await this.compress(message);
    }

    // Remove unnecessary fields
    message = this.stripUnnecessaryFields(message);

    // Use binary format for numeric data
    message = this.optimizeNumericData(message);

    return message;
  }

  async compress(data) {
    const json = JSON.stringify(data);
    const compressed = pako.deflate(json);

    return {
      compressed: true,
      data: base64Encode(compressed),
      originalSize: json.length,
      compressedSize: compressed.length
    };
  }

  batchMessages(messages) {
    const batches = [];

    for (let i = 0; i < messages.length; i += this.batchSize) {
      batches.push({
        type: 'batch',
        messages: messages.slice(i, i + this.batchSize),
        batchId: generateId(),
        timestamp: Date.now()
      });
    }

    return batches;
  }
}
```

### Connection Pooling

```javascript
class ConnectionPool {
  constructor(maxConnections = 10) {
    this.maxConnections = maxConnections;
    this.connections = [];
    this.available = [];
    this.inUse = new Map();
  }

  async getConnection() {
    // Return available connection
    if (this.available.length > 0) {
      const conn = this.available.pop();
      this.inUse.set(conn.id, conn);
      return conn;
    }

    // Create new if under limit
    if (this.connections.length < this.maxConnections) {
      const conn = await this.createConnection();
      this.connections.push(conn);
      this.inUse.set(conn.id, conn);
      return conn;
    }

    // Wait for available connection
    return this.waitForConnection();
  }

  releaseConnection(conn) {
    this.inUse.delete(conn.id);
    this.available.push(conn);
  }

  async createConnection() {
    const conn = new WebSocketConnection();
    await conn.connect();
    return conn;
  }
}
```

## Monitoring and Analytics

### Real-Time Metrics

```javascript
class RealtimeMetrics {
  metrics = {
    connections: {
      active: 0,
      peak: 0,
      failed: 0,
      reconnects: 0
    },

    messages: {
      sent: 0,
      received: 0,
      failed: 0,
      avgLatency: 0
    },

    performance: {
      cpuUsage: 0,
      memoryUsage: 0,
      bandwidth: 0,
      messageQueue: 0
    }
  };

  collectMetrics() {
    return {
      timestamp: Date.now(),
      ...this.metrics,

      channels: {
        active: this.getActiveChannels(),
        subscribers: this.getSubscriberCounts()
      },

      errors: {
        rate: this.getErrorRate(),
        types: this.getErrorTypes()
      }
    };
  }

  getHealthStatus() {
    const metrics = this.collectMetrics();

    return {
      status: this.calculateHealth(metrics),
      metrics: metrics,
      alerts: this.getActiveAlerts(),
      recommendations: this.getRecommendations(metrics)
    };
  }
}
```

## Scalability Strategies

### Horizontal Scaling

```javascript
const scalingConfig = {
  autoScaling: {
    enabled: true,
    minInstances: 2,
    maxInstances: 20,

    triggers: {
      connections: {
        threshold: 1000,
        scaleUp: 0.8,
        scaleDown: 0.3
      },

      cpu: {
        threshold: 0.7,
        duration: 300 // 5 minutes
      },

      messageRate: {
        threshold: 10000, // per second
        duration: 60
      }
    }
  },

  loadBalancing: {
    strategy: 'least-connections',
    healthCheck: '/health',
    stickySession: true
  },

  sharding: {
    enabled: true,
    strategy: 'tournament-based',
    rebalance: true
  }
};
```

## Testing Strategies

### Load Testing Configuration

```javascript
const loadTestConfig = {
  scenarios: [
    {
      name: 'Tournament Start',
      connections: 5000,
      messagesPerSecond: 1000,
      duration: 600 // 10 minutes
    },
    {
      name: 'Finals Rush',
      connections: 10000,
      messagesPerSecond: 5000,
      duration: 300 // 5 minutes
    }
  ],

  metrics: [
    'connection_time',
    'message_latency',
    'delivery_rate',
    'error_rate',
    'cpu_usage',
    'memory_usage'
  ]
};
```