# DWS ROBOT CONTROL FABRIC — POST-MVP ARCHITECTURE VISION

Status: `FUTURE / POST-MVP / NOT ACTIVATED`

Date: `2026-09-08`

Repository: `rootfabric/distributed-world-simulator`

## 1. Назначение документа

Этот документ фиксирует архитектурное направление для будущей поддержки большого количества автономных роботов, логика управления которых выполняется **вне simulation core** DWS.

Это **не Work Order**, не активная roadmap-ветка и не разрешение начинать реализацию сейчас.

К реализации следует возвращаться **после успешного завершения и стабилизации основного MVP DWS**, когда канонически доказаны базовые свойства мира: распределённая multi-region работа, seamless ownership/handoff, multi-client convergence, persistence/restart, физическое взаимодействие и базовая визуализация.

Цель текущей фиксации — не потерять архитектурные выводы и заранее задать правильные границы, чтобы будущий ROBOT-контур не пришлось строить заново после первых масштабных экспериментов.

---

## 2. Основная идея

Робот в DWS должен быть физическим субъектом мира, но его управляющая логика может выполняться снаружи симуляции: Python, C++, Rust, ROS2, RL runtime, LLM/agent runtime, специализированный controller worker или другой внешний процесс.

Критическая граница:

```text
EXTERNAL CONTROLLER
        |
        | actuator commands
        v
DWS ROBOT I/O FABRIC
        |
        v
VIRTUAL DEVICES
        |
        v
DWS PHYSICS / WORLD
```

Внешний controller не должен напрямую менять:

```text
body.position
body.rotation
body.velocity
wheel.rotation
```

Он должен воздействовать через виртуальные устройства:

```text
motor torque
motor current
motor voltage
PWM / throttle
servo target
brake command
```

Физическое состояние остаётся собственностью DWS.

Обратная связь должна поступать из фактического simulated state:

```text
encoder
IMU
motor current
battery voltage
joint state
contact state
lidar
camera
depth
other sensors
```

---

## 3. Базовая архитектурная граница

Simulation Core не должен превращаться в сетевой брокер.

Предпочтительная граница:

```text
                       EXTERNAL COMPUTE

             Python / C++ / Rust / ROS / AI
                          |
                          v
                Robot Control Fabric
                          |
                          v
                 Robot I/O Gateway
                          |
                    shared memory
                          |
                          v
                    DWS Core
```

`DWS Core` должен делать только горячую deterministic/physics работу:

```text
physics tick
    -> read actuator frame
    -> simulate
    -> sample device state
    -> write sensor frame
```

Сетевые соединения, reconnect, multiplexing, serialization, stream management, codec, camera relay и внешние SDK должны жить вне основного ядра.

---

## 4. Почему нельзя использовать один универсальный message broker для всех данных

Потоки робота имеют принципиально разные требования.

Например:

```text
motor command: десятки байт, высокий приоритет, deadline
camera frame: сотни KB / MB, высокая пропускная способность
lidar: крупный bulk frame
mode change: редкое, но обязано быть доставлено
encoder/IMU: частая telemetry, допустима потеря старого sample
```

Если всё положить в одну очередь, тяжёлые camera/lidar payload будут создавать head-of-line blocking для управления приводами.

Поэтому Robot Control Fabric должен иметь единое логическое адресное пространство, но несколько data planes.

---

## 5. Разделение Control Plane и Data Plane

### 5.1 Control Plane

Control Plane отвечает за:

```text
robot discovery
controller registration
session establishment
leases
controller ownership
authority epochs
region/gateway routing
device schema
subscriptions
configuration
fault events
service discovery
```

Для этого в будущем допустим полноценный брокер сообщений, например NATS-class system или собственный аналог.

Но broker не должен находиться в 500-1000 Hz hot path каждого двигателя.

Типичный сценарий:

```text
Controller registered
        |
        v
Control Plane assigns robots 1000..1199
        |
        v
returns realtime data-plane endpoint
        |
        v
hot path proceeds directly
```

### 5.2 Realtime Data Plane

Для быстрых команд и telemetry:

```text
same host     -> shared memory / ring buffers
remote host   -> QUIC datagrams or equivalent low-latency datagrams
```

### 5.3 Reliable Data Plane

Для событий, которые нельзя терять:

```text
mode changes
attach/detach
reset
configuration mutation
controller takeover
fault acknowledgement
```

Предпочтительно использовать ordered reliable stream, например QUIC Stream-class semantics.

### 5.4 Bulk Sensor Plane

Для:

```text
camera
stereo/depth
lidar
point clouds
large maps
large diagnostics
```

используется отдельный bulk transport.

Большие payload не должны проходить через realtime command queue.

---

## 6. QoS-классы

Предварительно зафиксировать минимум четыре класса:

| QoS class | Примеры | Семантика |
| --- | --- | --- |
| `RT_CONTROL` | torque, PWM, steering | минимальная задержка, deadline, latest command wins |
| `FAST_STATE` | encoder, IMU, battery | свежесть важнее полноты, старые samples можно терять |
| `RELIABLE_EVENT` | reset, mode, attach/detach | нельзя молча потерять, ordered/reliable |
| `BULK_SENSOR` | camera, lidar, depth | bandwidth + backpressure + subscription |

Эти классы должны быть частью protocol contract, а не случайной особенностью конкретной реализации транспорта.

---

## 7. Multiplexing вместо тысяч сокетов

Не создавать отдельное соединение для каждого мотора или каждого робота.

Неправильная модель:

```text
robot1.motor1 -> socket
robot1.motor2 -> socket
robot2.motor1 -> socket
...
```

Предпочтительная модель:

```text
Controller Worker connection
    |
    +-- robot 101
    |    +-- motor L
    |    +-- motor R
    |
    +-- robot 102
    |    +-- motor L
    |    +-- motor R
    |
    +-- ...
```

Один Controller Worker может обслуживать десятки/сотни роботов и отправлять батчи команд.

Пример:

```text
ActuatorFrame tick=918273

robot 1001:
    motor_l = 0.31
    motor_r = 0.34

robot 1002:
    motor_l = 0.84
    motor_r = 0.71

...
```

Simulation Core получает packed/batched representation, а не тысячи независимых сетевых callbacks.

---

## 8. Per-region Robot I/O Gateway

Каждый simulation region/server в будущем должен иметь внешний I/O sidecar:

```text
REGION NODE

+-----------------------+
| DWS Simulation Core   |
+-----------+-----------+
            | SHM
+-----------v-----------+
| Robot I/O Gateway     |
+-----------+-----------+
            |
        network fabric
```

Gateway отвечает за:

```text
network I/O
packet validation
session/epoch fencing
batching
routing
QoS
stream descriptors
backpressure
watchdogs
metrics
```

Core не должен выполнять эти функции на основном physics path.

---

## 9. Масштабирование Controller Workers

Цель должна предусматривать не один процесс на один робот, а worker pool.

Например:

```text
Controller Worker A -> robots 1..128
Controller Worker B -> robots 129..256
Controller Worker C -> robots 257..384
```

Внутри worker:

```text
receive SensorFrame batch
        |
        v
controller[robot_id].step(state)
        |
        v
build ActuatorFrame batch
```

Тяжёлые роботы могут иметь отдельный GPU/AI worker.

Массовые простые роботы могут работать в одном process/runtime.

---

## 10. Уровни локальности управления

Не каждый control loop рационально отправлять через удалённую сеть.

Предварительная модель:

```text
1-20 Hz
AI / planner / LLM / global behavior
remote compute допустим
        |
        v
50-200 Hz
motion control
local/remote network
        |
        v
500-2000 Hz
servo / motor control
near-sim controller worker
        |
        v
shared memory
        |
        v
DWS physics/device model
```

При этом controller по-прежнему логически находится **вне simulation core**.

Near-sim execution означает отдельный процесс/sandbox рядом с region server, а не загрузку пользовательского Python/C++ кода внутрь physics core.

---

## 11. Низкоуровневое устройство: мотор и колесо

Базовый actuator path:

```text
external controller
        |
    throttle / PWM / current / torque
        |
        v
virtual motor
        |
        v
joint / drivetrain
        |
        v
physical wheel
        |
        v
world contacts
```

Feedback path:

```text
physical shaft/joint
        |
        v
virtual encoder
        |
        v
Robot I/O Fabric
        |
        v
external controller
```

Нельзя формировать encoder feedback из команды двигателя. Feedback должен отражать реальное simulated движение.

Если колесо заблокировано:

```text
PWM = 100%
encoder velocity ~ 0
motor current high
```

Именно внешний controller должен иметь возможность диагностировать stall.

---

## 12. Поддерживаемые actuator modes

Архитектура должна допускать несколько уровней реализма:

```text
POSITION
VELOCITY
TORQUE
CURRENT
VOLTAGE
PWM
```

Возможные уровни:

| Level | External command | Purpose |
| --- | --- | --- |
| L0 | position / velocity | простые/массовые агенты |
| L1 | torque | нормальная robotics simulation |
| L2 | current / voltage / PWM | firmware-like SIL/HIL |

Для раннего ROBOT0 наиболее разумный кандидат — `TORQUE`, с последующим добавлением electrical motor model.

---

## 13. Tick, sequence, epoch и deadline

Realtime command должен содержать не только значение actuator.

Минимальная семантика:

```text
robot_id
device_id
authority_epoch
controller_epoch
sequence
sim_tick / target_tick
deadline / valid_until_tick
command payload
```

### sequence

Защищает от reorder/duplicate:

```text
#101 arrives
#100 arrives later -> DROP
```

### controller_epoch

Защищает от старого controller после takeover/restart.

### authority_epoch

Связывает command с текущим владельцем физического субъекта/region ownership.

### valid_until_tick

Предотвращает бесконечное продолжение последнего газа после падения внешнего process.

Если команда просрочена:

```text
CONTROL_TIMEOUT
    -> safe actuator state
    -> optional brake
```

---

## 14. Simulation clock является главным временем

Controller не должен полагаться только на wall-clock `sleep()`.

DWS должен передавать:

```text
sim_tick
sim_time
```

Это требуется для:

```text
pause
slow motion
accelerated simulation
replay
lockstep tests
deterministic verification
```

Для deterministic режима возможен lockstep:

```text
DWS state N
    -> SensorFrame N
controller
    -> ActuatorFrame N+1
DWS
    -> state N+1
```

Для живого distributed world используется async realtime mode с deadlines и zero-order hold/safe timeout policy.

---

## 15. Камеры: никогда не помещать raw frame в command broker

Camera plane должен быть отдельным.

Broker/Control Fabric передаёт только descriptor/control metadata:

```text
stream_id
frame_id
tick
timestamp
format
resolution
encoding
```

Сам frame идёт bulk path.

Локально возможны:

```text
shared memory frame pool
shared GPU buffer
zero-copy / near-zero-copy path
```

Удалённо:

```text
raw stream
compressed stream
H.264 / AV1-class encoding
other negotiated representation
```

---

## 16. Камеры должны быть subscription-driven

Необходимо избежать модели "каждая камера каждого робота всегда генерирует 30 FPS в сеть".

Controller должен запрашивать параметры:

```text
camera/front
fps = 10
resolution = 640x360
format = RGB
```

или:

```text
mode = ON_DEMAND
```

Если camera subscription отсутствует, не должно существовать обязательного полного внешнего видеопотока.

Будущий scheduler может учитывать стоимость сенсоров.

---

## 17. Backpressure и latest-frame semantics

Для live perception свежесть часто важнее полноты.

Если consumer обрабатывает frame 100, а producer уже создал 101..104, допустимо выдать 104 и отбросить промежуточные frames.

```text
LIVE PERCEPTION:
latest frame wins
```

Это отличается от recorder:

```text
RECORDING:
durable ordered stream
```

Эти режимы не должны использовать одну и ту же очередь без явной QoS policy.

---

## 18. LiDAR и другие тяжёлые сенсоры

LiDAR должен следовать той же схеме, что camera:

```text
metadata/control -> Robot Control Fabric
large data       -> Bulk Sensor Plane
```

В будущем можно negotiated representations:

```text
raw points
compressed points
voxelized cloud
range image
obstacle list
semantic result
```

Это позволяет не отправлять raw million-point cloud роботам, которым нужен только локальный obstacle representation.

---

## 19. Device addressing

Человекочитаемые пути полезны при discovery/configuration:

```text
robot_71831/front_left_wheel_motor
```

Но hot path должен использовать compact IDs.

После handshake:

```text
robot_id = 71831

1 = front_left_motor
2 = front_right_motor
3 = rear_left_motor
4 = rear_right_motor
5 = imu
6 = lidar
7 = front_camera
```

Дальше realtime packet может не повторять длинные строки.

---

## 20. Единый logical envelope

Предварительный логический envelope:

```text
protocol_version
message_type
robot_id
device_id
authority_epoch
controller_epoch
sequence
sim_tick
qos
deadline_tick
payload_type
payload / descriptor
```

Важно: единый logical envelope **не означает один физический transport**.

Например:

```text
MOTOR_COMMAND      -> realtime datagram
IMU_SAMPLE         -> realtime datagram
MODE_CHANGE        -> reliable stream
CAMERA_DESCRIPTOR  -> control/reliable metadata
CAMERA_FRAME       -> bulk stream
```

---

## 21. Seamless distributed ownership

Внешний controller не должен знать, какой region server сейчас владеет физическим роботом.

Логическая схема:

```text
Controller
    |
    v
Robot Control Router
    |
    +--> Gateway A   before handoff
    |
    +--> Gateway B   after handoff
```

Controller продолжает адресовать:

```text
robot_id = 71831
```

При seam handoff Router меняет route и authority epoch.

Старый server/gateway после handoff не должен иметь права применять команды прежней authority epoch.

Это должно быть согласовано с каноническими DWS owner/epoch/revision fencing contracts, а не создавать независимую конкурирующую модель ownership.

---

## 22. Internal data representation в Core

Gateway должен стремиться передавать Core батчи, удобные для cache locality/SIMD/parallel processing.

Предпочтительно избегать hot-path модели:

```text
Robot object
 -> Motor object
 -> virtual dispatch
 -> packet object
```

для каждого устройства.

Рассмотреть packed/SoA-like representation:

```text
robot_id[]
device_id[]
torque[]
mode[]
valid_until_tick[]
```

То же относится к encoder/state telemetry.

Конкретная representation должна выбираться только после profiling, но batch-first boundary стоит сохранить заранее.

---

## 23. Replay и observability

Robot I/O Fabric должен позволять журналировать:

```text
sim_tick
actuator frame
sensor frame metadata
controller epoch
authority epoch
routing transition
fault/timeout
```

Это даст возможность воспроизводить аварии без повторного запуска внешнего AI.

Например:

```text
recorded actuator stream
        |
        v
DWS replay
        |
        v
physical regression verification
```

Полные camera/lidar payload не обязаны входить в каждый базовый control log; для них может существовать отдельный optional recording plane.

---

## 24. Safety / failure semantics

Обязательные будущие failure modes:

```text
controller process crash
network loss
packet reorder
packet duplicate
stale command
controller takeover
region migration
Gateway restart
Core restart
slow consumer
camera backlog
bulk-stream congestion
```

RT control не должен блокироваться из-за bulk data congestion.

При потере lease/controller:

```text
lease expires
    -> invalidate controller epoch
    -> stop accepting old commands
    -> safe actuator state
    -> allow controlled reassignment
```

---

## 25. Предварительная масштабная цель

Архитектуру планировать минимум на следующий класс нагрузки:

```text
per region/server:
100-1000 physical robots
```

При этом число устройств может быть значительно больше числа роботов.

Пример для 1000 роботов:

```text
4 motors
4 encoders
1 IMU
1 battery
1 lidar
2 cameras
=
13 000 logical devices
```

Это ещё одна причина, почему нельзя строить architecture как "socket/process/thread per device".

Масштаб должен обеспечиваться:

```text
multiplexing
batching
worker pools
subscription-driven sensors
QoS separation
near-sim controller placement
shared-memory Core boundary
```

---

## 26. Возможная будущая top-level topology

```text
                         GLOBAL
              +------------------------+
              | Robot Control Broker   |
              |                        |
              | discovery              |
              | routing                |
              | leases                 |
              | ownership              |
              | subscriptions          |
              +-----------+------------+
                          |
           +--------------+---------------+
           |              |               |
           v              v               v

     REGION NODE A   REGION NODE B   REGION NODE C

     +-----------+   +-----------+
     | DWS Core  |   | DWS Core  |
     +-----+-----+   +-----+-----+
           | SHM             | SHM
     +-----v-----+     +-----v-----+
     | I/O Edge  |     | I/O Edge  |
     | Gateway   |     | Gateway   |
     +--+-----+--+     +-----------+
        |     |
        |     +------------- Bulk Sensor Plane
        |
        +------------------- Realtime / Controller Workers
```

---

## 27. External SDK должен скрывать transport

Пользовательский API должен быть логически простым:

```python
robot = await dws.robot("robot-71831")

async for frame in robot.control_frames():
    left = controller.left(frame)
    right = controller.right(frame)

    await robot.actuators.commit(
        left_motor=left,
        right_motor=right,
    )
```

SDK внутри может выбрать:

```text
shared memory
QUIC datagram
reliable stream
bulk stream
```

без изменения controller application API.

При region migration user code также не должен переподключаться вручную.

---

## 28. Потенциальная связь с SIL/HIL

Такая граница позволяет в перспективе запускать один и тот же controller против:

```text
DWS virtual devices
```

или через adapter против:

```text
CAN
EtherCAT
UART
real motor controller
real sensors
```

Это открывает путь к Software-In-The-Loop и Hardware-In-The-Loop без необходимости превращать DWS в ROS-specific runtime.

ROS2 должен рассматриваться как adapter/bridge поверх DWS Robot Device Protocol, а не как обязательный transport ядра.

---

## 29. Что НЕ делать до MVP

До успешного MVP не следует:

```text
реализовывать Robot Control Broker
встраивать ROS2 в core
строить camera streaming infrastructure
писать distributed controller scheduler
оптимизировать 1000 Hz loops
строить WASM/controller sandbox
вводить новый ownership model
```

Текущий документ должен оставаться архитектурной закладкой.

Разработка этого контура не должна отвлекать основную ветку от завершения MVP.

---

## 30. Когда активировать работу

Вернуться к этому направлению только после канонического post-MVP решения.

Минимальные предварительные prerequisites:

```text
MVP accepted
multi-region ownership/handoff stable
multi-client convergence stable
persistence/restart stable
basic physical manipulation stable
observability/profiling sufficient
```

После этого сначала провести новый fresh architecture audit относительно фактической на тот момент topology DWS.

Нельзя считать сегодняшний transport choice окончательным: QUIC, NATS, shared-memory layout, codec и конкретные frequencies должны быть перепроверены по актуальному состоянию проекта и benchmark-данным.

---

## 31. Предварительная post-MVP дорожка, не активированная сейчас

```text
ROBOT-A0  Fresh architecture reconciliation after MVP
    |
ROBOT-A1  Device / actuator / sensor contracts
    |
ROBOT-A2  Single external controller + single motor closed loop
    |
ROBOT-A3  Two-wheel physical robot + encoder/IMU feedback
    |
ROBOT-A4  Per-region I/O Gateway + Core shared-memory boundary
    |
ROBOT-A5  Multiplexed Controller Workers + batching
    |
ROBOT-A6  Distributed routing + seamless region handoff
    |
ROBOT-A7  QoS split: RT / reliable / bulk
    |
ROBOT-A8  Camera/LiDAR subscription + backpressure
    |
ROBOT-A9  100-robot scale campaign
    |
ROBOT-A10 1000-robot scale campaign
    |
ROBOT-A11 ROS2/SIL adapters
    |
ROBOT-A12 optional HIL bridge
```

Это только рабочая гипотеза будущей декомпозиции. Перед активацией она должна быть пересмотрена по фактической архитектуре post-MVP DWS.

---

## 32. Первый будущий bounded experiment

Когда направление будет разблокировано, начинать не с брокера и не с 1000 роботов, а с минимального доказательства границы:

```text
External Python PID
        <->
Realtime transport
        <->
Robot I/O Gateway
        <->
VirtualMotor
        <->
Physical Wheel
```

Acceptance-сценарий:

```text
external controller commands torque/throttle
wheel physically accelerates
encoder reports actual state
controller closes loop
controller crash triggers timeout/safe state
no direct body transform mutation exists
```

Только после доказательства этого контракта имеет смысл масштабировать fabric.

---

## 33. Зафиксированное архитектурное решение

На дату этого документа предпочтительное долгосрочное направление DWS:

```text
ROBOT CONTROL FABRIC
=
brokered control plane
+
multiplexed realtime data plane
+
reliable event plane
+
separate bulk sensor plane
+
per-region I/O sidecar
+
batched/shared-memory boundary to Simulation Core
```

Ключевые invariants:

1. Simulation Core остаётся владельцем физического состояния.
2. Внешний код управляет устройствами, а не transforms физического тела.
3. Core не обслуживает напрямую тысячи внешних сетевых соединений.
4. RT control не блокируется camera/lidar traffic.
5. Старые/stale controllers отсекаются epochs/leases/fencing.
6. Robot address остаётся логически стабильным при region handoff.
7. Bulk sensors работают через subscriptions и backpressure.
8. Один transport не навязывается всем классам сообщений.
9. Масштаб достигается batching/multiplexing/worker pools, а не thread/socket per device.
10. Реализация откладывается до успешного MVP и начинается с fresh architecture reconciliation.

---

## 34. Текущий статус

```text
DESIGN IDEA CAPTURED
IMPLEMENTATION = NOT STARTED
ACTIVATION = BLOCKED UNTIL POST-MVP
```

Этот документ должен использоваться после MVP как исходный материал для нового архитектурного аудита и формирования bounded Work Orders, но не как разрешение реализовывать контур сейчас.
