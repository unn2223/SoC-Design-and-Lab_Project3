# 2-Way Read-Only Cache Controller (AXI Read, 64B Line, WRAP Burst)
<img width="300" height="300" alt="image" src="https://github.com/user-attachments/assets/cfa5ea71-9d99-4ea2-9231-4cccf8497ff8" />


<img width="600" height="330" alt="image" src="https://github.com/user-attachments/assets/7bcef999-7890-46a6-9b25-48816c62d156" />


## 1. 프로젝트 소개

**AXI Read 요청**을 처리하는 **2-way read-only 캐시 컨트롤러** 설계 프로젝트입니다.  
요청 주소를 `Tag / Index / Offset`으로 분해해 **SRAM(Tag/Data array)**에서 hit/miss를 판정하고, miss 시에는 **메모리로 64B WRAP burst read(8 beats)**를 발행해 데이터를 받아오며, 이를 **프로세서에 전송 및 캐시 라인 fill**을 수행합니다.  
또한 hit 응답이 miss 응답보다 빨라서 발생할 수 있는 **out-of-order 응답 문제를 Reorder 구조로 해결**해, **항상 프로세서의 요청 순서대로(in-order) R 응답**이 나가도록 설계했습니다.

- **2-way tag compare** 기반 hit/miss 판정
- **WRAP burst(critical word first)** 순서에 맞춘 hit 응답 및 miss fill 처리
- hit/miss가 섞여도 **in-order 응답 보장(Reorder)**
- FIFO **AFULL 기반 backpressure**로 overflow 방지
- miss 시 **replacement policy(CC_WAY)**로 way 선택

## 2. 프로젝트 개요

### 요구사항 핵심
- Cache line: **64B**
- AXI Read 데이터 폭: **64-bit (= 8B/beat)**
- 한 번의 read 요청에 대한 응답은 항상 **64B(= 8 beats)** 단위로 처리한다.  
  - **HIT**: 캐시(SRAM)에 저장된 64B 라인을 읽어 **8 beat로 분할**해 응답  
  - **MISS**: 메모리에서 **8 beat**를 수신해 응답하며, 동시에 64B 라인으로 조립해 캐시에 저장(fill)

- AXI Read burst 파라미터
  - `ARSIZE = 3'b011` : 1 beat = **8B** (`2^3 = 8B`)
  - `ARLEN  = 7`      : 총 **8 beats** (`ARLEN + 1`)
  - `ARBURST = 2'b10 (WRAP)` : **WRAP burst mode**
    - WRAP boundary는 `(ARLEN+1) × 2^ARSIZE`로 결정
      따라서 `8 × 8B = 64B` -> **64B 범위 안에서 주소가 wrap**
    - 요청이 라인 중간(offset)에서 시작하면 **offset부터 먼저 처리**하고, 64B 끝에서 **라인 시작으로 돌아가** 나머지 beat를 처리합니다.
  - `ARADDR[2:0] = 3'b000` : **8B 정렬** (64-bit 전송이므로 하위 3비트는 0)

### 캐시 구성 (2-way)
- Address split (32-bit):
  - `Tag   = [31:14]` (18b)
  - `Index = [13:6]`  (8b)
  - `Offset= [5:0]`   (6b)
- `Index(8b)` -> 2^8= **256 sets**
- `2-way` -> set 당 2 라인
- `Line=64B` -> 라인당 64B
  - 전체 데이터 캐시 용량: `256 sets × 2 ways × 64B = 32KB`


## 3. 프로젝트 상세

### 3.1 Address (Tag/Index/Offset)
캐시가 주소를 전부 저장할 수는 없기 때문에,
- **Index**로 SRAM의 “행(set)”을 고르고,
- 그 set 안에 저장된 “이 라인이 어떤 주소의 데이터인지”는 **Tag**로 구분합니다.


Address[31:0]
| Tag[31:14] (18) | Index[13:6] (8) | Offset[5:0] (6) |

- 이때, SRAM은 2-way로 구성됩니다.
 - 즉, `index = 5`이면:
  - `tag0[5]`, `data0[5]` 와 `tag1[5]`, `data1[5]`를 동시에 읽고,
  - 요청 tag와 비교해 hit인지 판정합니다.



### 3.2 Hit 동작 (2-way compare -> Reorder -> WRAP 순서 응답)

프로세서 AR 요청 1건이 들어왔을 때 hit 경로는 아래 순서로 동작합니다.

**(1) AR handshake: SRAM read 요청**
- `CC_DECODER`가 입력 주소를 `tag/index/offset`으로 분해합니다.
- AR이 접수되면(`hs_pulse_o = ARVALID & ARREADY`), `CC_TOP`은 SRAM read를 시작합니다.  
  (`rden_o=1`, `raddr_o=index`)
- SRAM은 1-cycle latency이므로, `set[index]`의 way0/way1 tag/data는 다음 cycle에 출력됩니다.

**(2) 다음 cycle: 2-way tag compare로 hit 판정**
- `CC_TAG_COMPARATOR`가 way0/way1의 `{valid, tag}`를 각각 비교해 `hit0`, `hit1`을 생성합니다.
- `is_hit = hit0 | hit1`로 최종 hit 여부를 결정하고, hit인 경우 `hit_way`에 따라 해당 way의 64B line을 선택합니다.  
  (`hit_line_data = hit_way ? rdata_data1_i : rdata_data0_i`)

**(3) Reorder 입력: 요청 순서 토큰 + hit 데이터 적재**
- 요청 순서를 유지하기 위해 `Hit Flag FIFO`에는 모든 요청이 기록됩니다.
  - `hit_flag_fifo_wdata = is_hit` (hit=1, miss=0)
- hit인 경우에만 `Hit Data FIFO`에 `{offset, line(64B)}`를 저장합니다.
  - `hit_data_fifo_wdata = {offset_delayed, hit_line_data}`

**(4) Reorder 출력: WRAP(critical word first) 순서로 8 beat 응답**
- `CC_DATA_REORDER_UNIT`은 `Hit Flag FIFO`의 head가 hit(1)일 때 `Hit Data FIFO`를 꺼내,64B line을 8개의 beat로 분할해 프로세서 R 채널로 출력합니다.
- 출력 순서는 `base_word = offset[5:3]`부터 시작하며, 3-bit 덧셈을 이용해 자동으로 wrap됩니다.  
  (예: base=3이면 `W3,W4,W5,W6,W7,W0,W1,W2`)

> hit 데이터는 즉시 출력되지 않고, Reorder를 거친 뒤 토큰 순서에 맞춰 **항상 in-order**로 전달됩니다.



### 3.3 Miss 동작 (miss 판정 -> Memory AR 발행 -> Reorder 응답 + Fill -> SRAM write)

miss 경로는 **(A) 메모리에서 64B를 받아 프로세서로 전달**과  
**(B) 동일 데이터를 64B line으로 조립해 SRAM에 저장**이 동시에 진행됩니다.

**(1) miss 판정: 토큰 기록 + miss 데이터 저장**
- tag compare 결과 `is_hit=0`이면 miss입니다.
- 요청 순서를 위해 `Hit Flag FIFO`에 miss 토큰(0)을 기록합니다.
  - `hit_flag_fifo_wdata = 1'b0`
- Fill을 위해 miss 주소 데이터(= `{tag,index,offset}`로 복원된 32b 주소)를 `Miss Addr FIFO`에 저장합니다.
  - `miss_addr_wdata = {tag_delayed, index_delayed, offset_delayed}`

**(2) Memory AR 발행: issue_addr 선택 및 outstanding 관리**
- `CC_TOP`은 메모리 AR을 발행할 주소를 다음 우선순위로 선택합니다.
  1) `direct_hold_addr` : 이전 miss가 `mem_arready_i=0`으로 보류된 주소  
  2) `miss_req_fifo` head : 대기 중인 miss 요청 주소  
  3) `new_miss_addr` : 방금 발생한 miss 주소

- AR 요청이 실제로 접수되는 시점은 `mem_ar_fire = mem_arvalid_o & mem_arready_i`이며,
  이때부터 해당 line은 “메모리에서 가져오는 중(pending)”으로 간주된다.
- RTL은 `mem_outstanding`으로 현재 진행 중인 miss burst(8 beat)가 끝날 때까지
  다음 AR을 발행하지 않는 방식으로 관리합니다(동시에 1개 miss burst만 처리).

**(3) Memory R 수신: Reorder가 in-order로 프로세서에 전달**
- 메모리에서 들어오는 8 beat는 `CC_DATA_REORDER_UNIT`으로 입력됩니다.
- `Hit Flag FIFO`의 head가 miss(0)인 동안, Reorder는 메모리 R 데이터를 프로세서로 전달하며 burst 완료(rlast)까지 토큰(0)을 유지합니다.
- 프로세서 쪽이 `inct_rready_i=0`으로 막힐 수 있으므로, Reorder는 miss 데이터를
  - 필요 시 **miss beat FIFO**에 버퍼링하거나,
  - 바로 전달(bypass) 중 `ready=0`이 발생하면 **skid buffer(1-beat)**에 임시 저장합니다.

**(4) Cache Fill: WRAP 순서 재배치 -> 64B line 조립 -> SRAM write**
- `CC_DATA_FILL_UNIT`은 `Miss Addr FIFO`에서 `tag/index/offset`을 읽고, `base_word = offset[5:3]`를 저장합니다.
- WRAP burst에서는 메모리 RDATA가 `base_word = offset[5:3]`부터 순서대로 들어오며, 64B 경계에서 0으로 wrap됩니다.
- Fill Unit은 수신한 beat 번호(`beat_cnt`)를 이용해, 이번 beat가 라인 내부의 어느 8B word인지 계산한 뒤 해당 위치에 저장합니다.
  - `dst_word = (base_word + beat_cnt) mod 8`
  - `line_words[dst_word] <= mem_rdata_i`
  - 예: base_word=3이면 수신 순서 `W3,W4,W5,W6,W7,W0,W1,W2`를 각각 `line_words[3],...,[2]`에 저장해 최종적으로 `[W0..W7]` 라인을 완성합니다.
- 마지막 beat까지 수신(handshake)되면, Fill Unit은 라인 버퍼(`line_words[0..7]`)를 512b로 합친 후, SRAM에 write 합니다.
- SRAM에 write은 **마지막 beat(`mem_rlast_i`)가 handshake된 사이클**에 수행되며, 이때 아래 동작이 동시에 일어납니다.
  1) **SRAM write enable**을 1로 올려(`wren_o=1`) 캐시 라인 저장을 완료합니다.  
  2) 저장 위치는 `Miss Addr FIFO`의 miss 주소 메타데이터로부터 결정됩니다.  
     - `index = addr[13:6]` -> **SRAM의 set(row) 선택**  
     - `wway_o`(= `CC_WAY` 출력) -> **해당 set 안에서 way0/way1 중 write할 라인 선택**  
  3) 동일한 위치에 **Tag/Valid와 Data를 함께 갱신**합니다.  
     - Tag array에는 `{valid=1, tag}`를 기록하고  
     - Data array에는 `assembled_line(64B)`를 기록합니다.
  4) 저장이 끝나면, 이번 miss에 대응하던 **Miss Addr FIFO entry를 pop**하여 다음 miss fill로 진행합니다.
> 요약: 마지막 beat handshake 순간에, Fill Unit은 `index`로 set을 고르고 `CC_WAY`로 way를 선택한 뒤, `{valid,tag}`와 64B data를 함께 써서 라인 fill을 완료한다.
> miss는 Reorder를 통해 프로세서 응답을 **항상 in-order로 유지**하면서,  
> Fill Unit이 동일 데이터를 **offset 기반으로 재배치**해 64B line으로 조립한 뒤 SRAM에 저장합니다.

**중복 miss 방지 (cache line 단위)**
- 프로세서가 요청한 주소의 `addr[31:6]`가 같으면 **동일한 cache line**입니다.  
이때 CC_TOP은 이미 miss로 판정된 동일 line에 대한 **중복 miss 요청을 막기 위해**, 해당 line이 이미 miss 처리 중인지 아래 상태들을 통해 확인합니다.

 - **pending line**: 메모리로 AR 요청이 실제로 접수된 이후(`mem_arvalid & mem_arready`),  
  메모리 R 응답의 마지막 beat가 handshake될 때까지(`mem_rvalid & mem_rready & mem_rlast`) “가져오는 중”으로 표시
 - **miss fifo**: 아직 메모리 AR을 보내지 못했지만, miss로 판정되어 대기열(FIFO)에 올라가 있는 line들을 기록
 - **hold**: miss가 났지만 `mem_arready=0` 등으로 즉시 AR을 내보내지 못한 경우, 임시로 hold 주소를 저장

- 새로운 AR 요청이 들어왔을 때 `addr[31:6]`가 위 상태들 중 하나와 일치하면,  
그 요청은 중복 miss로 판정 후 즉시 접수하지 않고 **ARREADY를 0으로 내려** 잠시 대기시킵니다.  
위 상태가 해제되면 ARREADY를 다시 올려 요청을 접수하며, 이때 대부분 **hit로 처리**됩니다.



### 3.4 In-order 응답 보장 (Reorder)
hit은 SRAM에서 빠르게 나오고 miss는 메모리에서 늦게 오기 때문에,
요청이 여러 개 겹치면 hit 응답이 miss 응답을 앞설 수 있습니다.**(out-of-order)**

이를 최종적으로 reorder 수행 후 프로세서에 전달합니다.

- **Hit Flag FIFO** : 요청 순서대로 `hit(1) / miss(0)` 기록
- **Hit Data FIFO** : hit인 경우에만 `{offset, line(64B)}` 저장
- Reorder는 Hit Flag FIFO의 head를 보고:
  - head가 hit이면 -> Hit Data FIFO에서 꺼내 8 beat 출력
  - head가 miss이면 -> 메모리 R 데이터를 출력


### 3.6 Flow Control / Backpressure (AFULL)
여러 FIFO(hit_flag/data, miss_req/addr, id 등)가 overflow 되지 않도록, 입력 AR 채널의 `ARREADY`로 backpressure를 걸어 요청 접수를 제어합니다.

- **AFULL 기반 stall**: `CC_DECODER`는 관련 FIFO들의 `afull`(almost full) 상태를 모아 `stall`을 만들고,
  `stall=1`이면 `ARREADY=0`으로 내려 AR handshake를 잠시 중단합니다.
- **왜 AFULL이 필요한가? (1-cycle 지연 반영)**: SRAM read는 1-cycle latency이므로, AR을 받은 시점에 hit/miss가 즉시 결정되지 않고
  **다음 cycle**에야 hit/miss가 확정되며 그 결과에 따라 FIFO push가 발생합니다(예: hit이면 hit_data FIFO, miss이면 miss_req/miss_addr FIFO).
  따라서 FIFO가 완전히 가득 찬 뒤(full) 멈추면 늦을 수 있어, **almost-full(afull)** 단계에서 미리 AR을 막아 다음 cycle의 push까지 안전하게 수용할 수 있도록 설계했습니다.


## 4. Architecture (모듈 중심)

### 4.1 `CC_TOP`
**Top-level 통합 모듈**, 전체 시스템의 입출력과 주요 제어 담당

- INCT(프로세서측) AXI AR/R 인터페이스
- MEM(메모리측) AXI AR/R 인터페이스
- SRAM read/write 포트 제어
- 2-way compare 결과로 hit/miss 결정 후 Reorder/FIll에 분배
- ID 처리: `ARID`를 내부 FIFO에 저장하여 R 채널에서 `RID`로 반환
- 중복 miss 차단

**핵심 포인트**
- SRAM read는 `rden_o`/`raddr_o=index`로 제어 (AR handshake 타이밍)
- hit 시 reorder로 `{offset, line}` push
- miss 시 miss_req_fifo / miss_addr_fifo에 주소 metadata push, mem_ar 발행



### 4.2 `CC_DECODER`
주소 디코딩 + 입력 stall의 “가장 앞단” 역할

- `tag/index/offset` 조합 논리 분해
- 다양한 FIFO의 `afull` 상태를 OR 해서 `inct_arready_o`를 제어
- `hs_pulse_o = arvalid & arready` 형태의 handshake pulse 생성



### 4.3 `CC_TAG_COMPARATOR`
SRAM 1-cycle latency를 고려해 **tag compare 타이밍을 맞추는 모듈**

- handshake cycle에 `tag/index/offset`을 레지스터에 저장
- 다음 cycle에 SRAM tag `{valid, tag}`와 비교
- `hit_o`, `hs_pulse_delayed_o`를 생성

`CC_TOP`에서 way0/way1 각각 1개씩 인스턴스해 2-way compare를 구성



### 4.4 `CC_DATA_REORDER_UNIT`
**in-order 응답 보장**의 핵심 모듈

구성 요소
- 내부 `Hit Flag FIFO`
- 내부 `Hit Data FIFO` (offset+line 저장)
- 내부 `Miss Beat FIFO` (mem R 데이터를 저장할 수 있는 버퍼)
- miss direct bypass + skid buffer(ready=0 대응)

동작
- Hit Flag FIFO head를 보고 “이번 응답이 hit인지 miss인지” 결정
- hit: 저장된 라인을 WRAP 순서로 8 beat 출력
- miss: mem에서 오는 데이터를 inct로 전달(필요시 FIFO/스키드 사용)
- burst 완료(rlast) 시 토큰 pop 진행



### 4.5 `CC_DATA_FILL_UNIT`
miss 시 들어오는 8 beat로 **캐시 라인(64B)을 완성**하고 SRAM에 write

- Miss Addr FIFO에서 `tag,index,offset` metadata를 읽음
- `offset[5:3]`를 base로 하여 WRAP 순서로 들어오는 beat를 “원래 라인 위치”로 재배치(deserialize)
- 마지막 beat handshake에서:
  - `wren_o=1`, `waddr_o=index`, `wdata_tag_o={1,tag}`, `wdata_data_o=512b line` write
  - Miss Addr FIFO pop



### 4.6 `CC_WAY`
2-way에서 miss fill 시 write할 way를 결정

- LFSR 기반 pseudo-random way 선택
- fill commit 시점에 update



### 4.7 `CC_FIFO`
프로젝트 전반에서 사용하는 공통 FIFO

- `full/empty`, `afull/aempty`

### 4.8 `CC_CFG`
APB 레지스터 블록

- address 0x0 read 시 버전 값 반환(예: `32'h0002_2025`)



### 4.9 `CC_SERIALIZER`
- Hit 경로에서 선택된 64B cache line(512b)을 **8개의 64b beat**로 분할해 출력하는 모듈이며,  
`offset[5:3]`(base word)을 기준으로 **WRAP(critical word first) 순서**를 생성합니다.

- `CC_DATA_REORDER_UNIT`이 `CC_SERIALIZER`를 인스턴스하여 사용하며,
Reorder가 `Hit Flag FIFO`의 head가 hit(1)인 경우에만 serializer가 `Hit Data FIFO`를 pop 하도록 하여 요청 순서(in-order)를 유지합니다.
