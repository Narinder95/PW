enum PetState { idle, walking, playing, sleeping, celebrating, meditating, exercising, drinking_water, reading }

enum EnvironmentType { garden, forest, mountain, sky }

class Vector2D {
  double x;
  double y;

  Vector2D({required this.x, required this.y});

  Vector2D operator +(Vector2D other) => Vector2D(x: x + other.x, y: y + other.y);
  Vector2D operator *(double scalar) => Vector2D(x: x * scalar, y: y * scalar);
}

class JourneyPet {
  Vector2D position;
  Vector2D velocity;
  PetState state;
  double animationFrame;
  String petSpecies;
  int level;

  JourneyPet({
    required this.position,
    required this.petSpecies,
    Vector2D? velocity,
    this.state = PetState.idle,
    this.animationFrame = 0,
    this.level = 1,
  }) : velocity = velocity ?? Vector2D(x: 0, y: 0);

  void update(double deltaTime) {
    position = position + velocity * deltaTime;
    animationFrame = (animationFrame + deltaTime * 8) % 4; // 4-frame animation
  }
}

class EnvironmentObject {
  final String id;
  Vector2D position;
  Vector2D size;
  String assetName;
  bool isInteractive;
  double depth; // For z-ordering (0-1, higher = in front)

  EnvironmentObject({
    required this.id,
    required this.position,
    required this.size,
    required this.assetName,
    this.isInteractive = false,
    this.depth = 0.5,
  });
}

class JourneyWorld {
  // World dimensions
  late double width;
  late double height;

  // World state
  late JourneyPet pet;
  late EnvironmentType currentEnvironment;
  final List<EnvironmentObject> objects = [];
  final List<ParticleEmitter> particles = [];

  // Activity stats (for display)
  int stepsToday;
  int stepsGoal;
  int waterIntake;
  int exerciseMinutes;
  int sleepHours;

  JourneyWorld({
    this.stepsToday = 0,
    this.stepsGoal = 10000,
    this.waterIntake = 0,
    this.exerciseMinutes = 0,
    this.sleepHours = 0,
  });

  void initialize(double w, double h, {String petSpecies = '🐶'}) {
    width = w;
    height = h;

    pet = JourneyPet(
      position: Vector2D(x: w * 0.3, y: h * 0.6),
      petSpecies: petSpecies,
    );

    currentEnvironment = EnvironmentType.garden;
    _loadEnvironmentObjects();
  }

  void _loadEnvironmentObjects() {
    objects.clear();

    // Background elements
    objects.addAll([
      EnvironmentObject(
        id: 'sky',
        position: Vector2D(x: 0, y: 0),
        size: Vector2D(x: width, y: height * 0.4),
        assetName: 'sky_background',
        depth: 0.1,
      ),
      EnvironmentObject(
        id: 'ground',
        position: Vector2D(x: 0, y: height * 0.65),
        size: Vector2D(x: width, y: height * 0.35),
        assetName: 'ground_base',
        depth: 0.2,
      ),
      EnvironmentObject(
        id: 'tree_left',
        position: Vector2D(x: width * 0.1, y: height * 0.45),
        size: Vector2D(x: width * 0.15, y: height * 0.35),
        assetName: 'tree_large',
        depth: 0.3,
      ),
      EnvironmentObject(
        id: 'tree_right',
        position: Vector2D(x: width * 0.8, y: height * 0.5),
        size: Vector2D(x: width * 0.18, y: height * 0.3),
        assetName: 'tree_large',
        depth: 0.3,
      ),
      EnvironmentObject(
        id: 'structure_1',
        position: Vector2D(x: width * 0.7, y: height * 0.55),
        size: Vector2D(x: width * 0.12, y: height * 0.25),
        assetName: 'banner_structure',
        isInteractive: true,
        depth: 0.4,
      ),
    ]);
  }

  void update(double deltaTime) {
    pet.update(deltaTime);

    // Keep pet within bounds
    if (pet.position.x < 0) pet.position.x = 0;
    if (pet.position.x > width) pet.position.x = width;
    if (pet.position.y > height * 0.65) pet.position.y = height * 0.65;
    if (pet.position.y < height * 0.4) pet.position.y = height * 0.4;

    // Update particles
    for (var emitter in particles) {
      emitter.update(deltaTime);
    }
    particles.removeWhere((p) => p.isDead);
  }

  void petMove(double direction) {
    print('🚶 petMove($direction) called - changing state from ${pet.state} to ${direction != 0 ? "walking" : "idle"}');
    pet.velocity.x = direction * 100; // pixels per second
    pet.state = direction != 0 ? PetState.walking : PetState.idle;
  }

  void petPlay() {
    pet.state = PetState.playing;
    pet.velocity.x = 0;
    pet.animationFrame = 0;
  }

  void petSleep() {
    pet.state = PetState.sleeping;
    pet.velocity.x = 0;
  }

  void celebrate() {
    pet.state = PetState.celebrating;
    spawnCelebrationParticles();
  }

  void petMeditate() {
    print('🧘 petMeditate() called - setting pet.state to meditating');
    pet.state = PetState.meditating;
    pet.velocity.x = 0;
    pet.animationFrame = 0;
    print('🧘 Pet state is now: ${pet.state}');
  }

  void petExercise() {
    print('💪 petExercise() called - setting pet.state to exercising');
    pet.state = PetState.exercising;
    pet.velocity.x = 0;
    pet.animationFrame = 0;
    print('💪 Pet state is now: ${pet.state}');
  }

  void petDrinkWater() {
    print('💧 petDrinkWater() called - setting pet.state to drinking_water');
    pet.state = PetState.drinking_water;
    pet.velocity.x = 0;
    pet.animationFrame = 0;
    print('💧 Pet state is now: ${pet.state}');
  }

  void petRead() {
    print('📚 petRead() called - setting pet.state to reading');
    pet.state = PetState.reading;
    pet.velocity.x = 0;
    pet.animationFrame = 0;
    print('📚 Pet state is now: ${pet.state}');
  }

  void spawnCelebrationParticles() {
    particles.add(
      ParticleEmitter(
        position: pet.position,
        particleCount: 15,
        duration: 1.5,
      ),
    );
  }

  void updateActivityStats({
    int? steps,
    int? stepsGoal,
    int? water,
    int? exercise,
    int? sleep,
  }) {
    if (steps != null) stepsToday = steps;
    if (stepsGoal != null) this.stepsGoal = stepsGoal;
    if (water != null) waterIntake = water;
    if (exercise != null) exerciseMinutes = exercise;
    if (sleep != null) sleepHours = sleep;
  }
}

class ParticleEmitter {
  Vector2D position;
  final int particleCount;
  final double duration;
  double elapsedTime = 0;
  bool isDead = false;

  ParticleEmitter({
    required this.position,
    this.particleCount = 10,
    this.duration = 1.0,
  });

  void update(double deltaTime) {
    elapsedTime += deltaTime;
    if (elapsedTime >= duration) {
      isDead = true;
    }
  }

  double getProgress() => (elapsedTime / duration).clamp(0.0, 1.0);
}
