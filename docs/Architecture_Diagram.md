# Custom 32-Bit Pipelined FPGA Microcontroller Architecture Diagram

The microcontroller follows a **Harvard Architecture** with separate instruction and data paths, operating over a **5-stage pipeline**. The system architecture is visualized using the Mermaid diagram below:

```mermaid
graph TD
    %% Define Pipeline Stages
    subgraph IF_Stage [1. Instruction Fetch - IF]
        PC[Program Counter] --> |Address| IROM[Instruction ROM]
        IROM --> |Instr Word| IR[Instruction Register]
    end

    subgraph ID_Stage [2. Instruction Decode - ID]
        IR --> |Decode Fields| Decoder[Instruction Decoder]
        Decoder --> |Opcode| CU[Control Unit]
        CU --> |Register Addrs| RF[(32x32 Register File)]
        RF --> |Read Data rs1/rs2| ID_EX_Latch[ID/EX Pipeline Register]
    end

    subgraph EX_Stage [3. Execute - EX]
        ID_EX_Latch --> |rs1/rs2 data| FwdMux[Forwarding Multiplexers]
        FwdMux --> |Operands A/B| ALU[Arithmetic Logic Unit]
        FwdMux --> |Branch Values| BU[Branch Unit]
        ALU --> |Status Flags| SR[Status Register]
        BU --> |Corrected PC| PC
    end

    subgraph MEM_Stage [4. Memory Access - MEM]
        EX_MEM_Latch[EX/MEM Pipeline Register] --> |ALU Result / Address| MemCtrl[Memory Controller & Address Decoder]
        MemCtrl --> |Select & Enable| DRAM[(32KB Data RAM)]
        MemCtrl --> |Select & Enable| BootROM[(1KB Boot ROM)]
        MemCtrl --> |Select & Enable| Periph[MMIO Peripherals]
    end

    subgraph WB_Stage [5. Writeback - WB]
        MEM_WB_Latch[MEM/WB Pipeline Register] --> |Result Select| WBMux[Writeback Multiplexer]
        WBMux --> |Write Data| RF
    end

    %% Hazard Control and Forwarding Paths
    FwdUnit[Data Forwarding Unit] -.-> |Select Control| FwdMux
    HazardUnit[Hazard Detection Unit] -.-> |Stall / Flush| PC
    HazardUnit -.-> |Flush Bubbles| IR
    HazardUnit -.-> |Flush Bubbles| ID_EX_Latch

    %% Signal Connections to Forwarding Unit
    EX_MEM_Latch -.-> |Forward EX Result| FwdUnit
    MEM_WB_Latch -.-> |Forward MEM Result| FwdUnit

    %% Peripherals Details
    subgraph MMIO Peripherals
        Periph --> GPIO[GPIO Configurable]
        Periph --> UART[UART Controller]
        Periph --> SPI[SPI Master]
        Periph --> I2C[I2C Master]
        Periph --> Timer[Programmable Timer]
        Periph --> PWM[4-Ch PWM]
        Periph --> PIC[Priority Interrupt Controller]
        Periph --> WDT[Watchdog & CRC]
    end

    %% Styles
    style PC fill:#f9f,stroke:#333,stroke-width:2px
    style IROM fill:#bbf,stroke:#333,stroke-width:2px
    style DRAM fill:#bbf,stroke:#333,stroke-width:2px
    style RF fill:#bfb,stroke:#333,stroke-width:2px
    style ALU fill:#fbb,stroke:#333,stroke-width:2px
    style HazardUnit fill:#ffb,stroke:#333,stroke-width:2px
```
