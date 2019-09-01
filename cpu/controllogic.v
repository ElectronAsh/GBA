//****************************************************************************************************
// Control logic for ARM7TDMI-S processor
// Designed by Ruslan Lepetenok
// Modified 11.02.2003
// Version 0.2A
// LDM/STM state machines have been significantly changed (not tested yet)
//****************************************************************************************************

module controllogic(
   nRESET,
   CLK,
   CLKEN,
   BigEndianMode,
   InstForDecode,
   InstFetchAbort,
   StagnatePipeline,
   StagnatePipelineDel,
   FirstInstFetch,
   SignExt,
   ZeroExt,
   nB_HW,
   EndianMode,
   StoreHalfWord,
   StoreByte,
   ExceptionVector,
   PCInSel,
   ALUInSel,
   ExceptionVectorSel,
   PCIncStep,
   AdrIncStep,
   AdrToPCSel,
   AdrCntEn,
   InvA,
   InvB,
   PassA,
   PassB,
   AND_Op,
   ORR_Op,
   EOR_Op,
   CFlagUse,
   CFlagOut,
   VFlagOut,
   NFlagOut,
   ZFlagOut,
   LoadRsRm,
   LoadPS,
   ClearPSC,
   UnsignedMul,
   ReadLH,
   MulResRdy,
   ABusRdAdr,
   BBusRdAdr,
   WriteAdr,
   WrEn,
   PCWrEn,
   PCSrcSel,
   RFMode,
   SaveBaseReg,
   RestoreBaseReg,
   PSRDInSel,
   CPSRIn,
   CPSRWrEn,
   CPSROut,
   CFlForMul,
   SPSRIn,
   SPSROut,
   SPSRWrMsk,
   PSRMode,
   ShLenImm,
   ShType,
   ShRotImm,
   ShEn,
   ShCFlagEn,
   RegFileAOutSel,
   MultiplierAOutSel,
   CPSROutSel,
   SPSROutSel,
   RegFileBOutSel,
   MultiplierBOutSel,
   MemDataRegOutSel,
   SExtOffset24BitSel,
   Offset12BitSel,
   Offset8BitSel,
   Immediate8BitSel,
   AdrGenDataSel,
   RegisterList,
   IncBeforeSel,
   DecBeforeSel,
   DecAfterSel,
   MltAdrSel,
   SngMltSel,
   ClrBitZero,
   ClrBitOne,
   SetBitZero,
   ThumbDecoderEn,
   ThBLFP,
   ThBLSP,
   RmBitZero,
   Addr,
   DataAddrLow,
   nIRQ,
   nFIQ,
   ABORT,
   WRITE,
   SIZE,
   PREEMPTABLE
);
  // ARM core modes (CPSR [4:0]) 
parameter [4:0]  CUserMode = 5'b10000;
parameter [4:0]  CFIQMode = 5'b10001;
parameter [4:0]  CIRQMode = 5'b10010;
parameter [4:0]  CSVCMode = 5'b10011;
parameter [4:0]  CAbortMode = 5'b10111;
parameter [4:0]  CUndefMode = 5'b11011;
parameter [4:0]  CSystemMode = 5'b11111;

parameter [31:0] CPSRInitVal = { {24{1'b0}}, 3'b110, CSVCMode};

// Exception vector adressses 
parameter [31:0] CExcAdrUndefined = 32'h0000_0004;
parameter [31:0] CExcAdrSWI = 32'h0000_0008;
parameter [31:0] CExcAdrPrfAbt = 32'h0000_000C;
parameter [31:0] CExcAdrDtAbt = 32'h0000_0010;
parameter [31:0] CExcAdrIRQ = 32'h0000_0018;
parameter [31:0] CExcAdrFIQ = 32'h0000_001C;
  
// Bus transaction sizes (SIZE[1:0]) 
parameter [1:0]  CTS_B = 2'b00;		// Byte  
parameter [1:0]  CTS_HW = 2'b01;		// Halfword (16 bit) 
parameter [1:0]  CTS_W = 2'b10;		// Word(32 bit)	 
  
   parameter [3:0]  CR_PC = 4'b1111;		// PC(R15) 
   parameter [3:0]  CR_LR = 4'b1110;		// LR(R14) 
	
   // Clock and reset
   input           nRESET;
   input           CLK;
   input           CLKEN;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Control signals commom for several modules
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output          BigEndianMode;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Instruction pipeline and data in registers control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Interfaces for the internal CPU modules
   input [31:0]    InstForDecode;
   input           InstFetchAbort;
   output          StagnatePipeline;
   output          StagnatePipelineDel;
   output          FirstInstFetch;
   // Data out register and control(sign/zero, byte/halfword  extension)
   output          SignExt;
   reg             SignExt;
   output          ZeroExt;
   reg             ZeroExt;
   output          nB_HW;
   reg             nB_HW;
   // Bus control
   output          EndianMode;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Data output register control
   //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output          StoreHalfWord;
   reg             StoreHalfWord;
   output          StoreByte;
   reg             StoreByte;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Address multiplexer and incrementer control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output [31:0]   ExceptionVector;
   output          PCInSel;
   output          ALUInSel;
   output          ExceptionVectorSel;
   output          PCIncStep;		// ?? Common  1
   output          AdrIncStep;
   output          AdrToPCSel;
   output          AdrCntEn;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // ALU control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output reg      InvA;
   output reg      InvB;
   output          PassA;
   output          PassB;		// MOV/MVN operations
   // Logic operations
   output reg      AND_Op;
   output reg      ORR_Op;
   output reg      EOR_Op;
   output reg      CFlagUse;		// ADC/SBC/RSC instructions
   // Flag outputs
   input           CFlagOut;
   input           VFlagOut;
   input           NFlagOut;
   input           ZFlagOut;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Multiplier control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output          LoadRsRm;		// Load Rs and Rm and start
   output          LoadPS;		// Load partial sum register with RHi:RLo
   output          ClearPSC;		// Clear prtial sum register
   output          UnsignedMul;		// Unsigned multiplication
   output          ReadLH;		// 0 - Read PS/PC low,1 - Read PS/PC high
   input           MulResRdy;		// Multiplication result is ready
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Register file control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output [3:0]    ABusRdAdr;
   output [3:0]    BBusRdAdr;
   output [3:0]    WriteAdr;
   output          WrEn;
   // Program counter
   output          PCWrEn;
   output          PCSrcSel;
   // Mode control signals
   output [4:0]    RFMode;
   output          SaveBaseReg;
   output          RestoreBaseReg;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Programm Status Registers control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // ALU bus input control
   output          PSRDInSel;
   // Current program state
   output [31:0]   CPSRIn;
   output [31:0]   CPSRWrEn;
   input [31:0]    CPSROut;
   output          CFlForMul;
   // Saved program state
   output [31:0]   SPSRIn;
   input [31:0]    SPSROut;
   output [3:0]    SPSRWrMsk;
   // PSR mode control
   output [4:0]    PSRMode;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Shifter control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   //	                   ShCFlagIn  : out std_logic;                     -- Input of the carry flag
   //					   ShCFlagOut : in  std_logic;                     -- Output of the carry flag
   output reg [4:0] ShLenImm;		// Shift amount for immediate shift (bits [11..7])
   output reg [2:0]    ShType;		// Shift type (bits 6,5 and 4 of instruction)
   output reg      ShRotImm;		// Rotate immediate 8-bit value
   output reg      ShEn;
   output reg      ShCFlagEn;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Bus A multiplexer control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output          RegFileAOutSel;
   output          MultiplierAOutSel;
   output          CPSROutSel;
   output          SPSROutSel;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Bus B multiplexer control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output reg      RegFileBOutSel;		// Output of the register file
   output reg      MultiplierBOutSel;		// Output of the multiplier
   output reg      MemDataRegOutSel;		// Output of the data in register
   output reg      SExtOffset24BitSel;
   output reg      Offset12BitSel;
   output reg      Offset8BitSel;
   output reg      Immediate8BitSel;
   output reg      AdrGenDataSel;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Address generator for Load/Store instructions control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output [15:0]   RegisterList;
   output          IncBeforeSel;
   output          DecBeforeSel;
   output          DecAfterSel;
   output          MltAdrSel;
   output          SngMltSel;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Bit 0,1 clear/set control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output          ClrBitZero;
   output          ClrBitOne;
   output          SetBitZero;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Thumb decoder control
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   output          ThumbDecoderEn;
   input           ThBLFP;
   input           ThBLSP;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Rm[0] input for ARM/Thumb state detection during BX
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   input           RmBitZero;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // AddrLow for DataRotator in IPDR
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   input [31:0]    Addr;
   output [1:0]    DataAddrLow;
   
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // External signals
   // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   // Interrupts
   input           nIRQ;
   input           nFIQ;
   // Memory interface
   input           ABORT;
   output          WRITE;
   output [1:0]    SIZE;
   output          PREEMPTABLE;
   
   
   reg [31:0]      LastAddr;
   
   // Saved value of InstForDecode input(valid for the whole time of instruction execution)
   reg [31:0]      InstForDecodeLatched = 32'h00000000;
   
   // Saved abort flag
   reg             IFAbtStored;
   
   wire [3:0] opcode = InstForDecode[24:21];
   wire [4:0] shift_amount = InstForDecode[11:7];
   wire [1:0] shift = InstForDecode[6:5];
   wire [3:0] rotate = InstForDecode[11:8];
   
   wire [15:0] register_list = InstForDecode[15:0];
   
   //alias offset24b     : std_logic_vector(23 downto 0) is InstForDecode(23 downto 0);
   wire [23:0] swi_number = InstForDecode[23:0];
   
   wire [3:0] cond = InstForDecodeLatched[31:28];
   wire [3:0] Mask = InstForDecodeLatched[19:16];
   
   // Load/store fields !!! TBD
   wire U = InstForDecode[23];
   wire P = InstForDecode[24];
   wire W = InstForDecode[21];
   
   // Latched 	load/store fields
   wire U_Latched = InstForDecodeLatched[23];
   wire P_Latched = InstForDecodeLatched[24];
   wire W_Latched = InstForDecodeLatched[21];
   
   wire S_Latched = InstForDecodeLatched[20];
   wire R_Latched = InstForDecodeLatched[22];
   
   wire L_Latched = InstForDecodeLatched[20];		// '1' - Load / '0' - Store
   
   // Registers
   wire [3:0] Rn = InstForDecodeLatched[19:16];
   wire [3:0] Rd = InstForDecodeLatched[15:12];
   wire [3:0] Rs = InstForDecodeLatched[11:8];
   wire [3:0] Rm = InstForDecodeLatched[3:0];
   // Multiplication
   wire [3:0] RdM = InstForDecodeLatched[19:16];
   wire [3:0] RnM = InstForDecodeLatched[15:12];
   wire [3:0] RdHi = InstForDecodeLatched[19:16];
   wire [3:0] RdLo = InstForDecodeLatched[15:12];
   
   parameter [3:0] SBO = 4'b1111;
   parameter [3:0] SBZ = 4'b0000;
   
   wire            WriteToPC;		// Write to R15
   wire            WriteToHiFl;		// Data processing instruction writes to N,Z,C,V flags of CPSR
   wire            RestCPSR;		// Restore CPSR from the appropriate SPSR
   wire            WriteToCPSR;		// Write to CPSR
   wire            MulFlWr;			// Write to Z and C flag by multiplications
   
   // Instructions
   
   // Data processing instructions
   wire            IDC_AND;
   wire            IDC_EOR;
   wire            IDC_ORR;
   wire            IDC_BIC;
   wire            IDC_TST;
   wire            IDC_TEQ;
   wire            IDC_ADD;
   wire            IDC_ADC;
   wire            IDC_SUB;
   wire            IDC_SBC;
   wire            IDC_RSB;
   wire            IDC_RSC;
   wire            IDC_CMP;
   wire            IDC_CMN;
   wire            IDC_MOV;
   wire            IDC_MVN;
   
   // Multiplications
   wire            IDC_MUL;
   wire            IDC_MLA;
   wire            IDC_UMULL;
   wire            IDC_UMLAL;
   wire            IDC_SMULL;
   wire            IDC_SMLAL;
   
   //SPSR Move
   wire            IDC_MSR_R;		// Register operand
   wire            IDC_MSR_I;		// Immediate operand
   wire            IDC_MRS;
   
   // Branch
   wire            IDC_B;
   wire            IDC_BL;
   wire            IDC_BX;
   
   // Load
   wire            IDC_LDR;
   wire            IDC_LDRT;
   wire            IDC_LDRB;
   wire            IDC_LDRBT;
   wire            IDC_LDRSB;
   wire            IDC_LDRH;
   wire            IDC_LDRSH;
   
   wire            IDC_LDM;		// ?? Variants
   
   // Store
   wire            IDC_STR;
   wire            IDC_STRT;
   wire            IDC_STRB;
   wire            IDC_STRBT;
   wire            IDC_STRH;
   
   wire            IDC_STM;		// ?? Variants
   
   // Swap
   wire            IDC_SWP;
   wire            IDC_SWPB;
   
   wire            IDC_SWI;
   
   // Coprocessor communication instructions
   wire            IDC_MRC;
   wire            IDC_MCR;
   wire            IDC_LDC;
   wire            IDC_CDP;
   wire            IDC_STC;
   
   // Undefined instruction
   wire            IDC_Undef;
   
   // End of instruction decoder signals
   
   // Registeres instruction decoder outputs
   // Data processing instructions
   reg             IDR_AND;
   reg             IDR_EOR;
   reg             IDR_ORR;
   reg             IDR_BIC;
   reg             IDR_TST;
   reg             IDR_TEQ;
   reg             IDR_ADD;
   reg             IDR_ADC;
   reg             IDR_SUB;
   reg             IDR_SBC;
   reg             IDR_RSB;
   reg             IDR_RSC;
   reg             IDR_CMP;
   reg             IDR_CMN;
   reg             IDR_MOV;
   reg             IDR_MVN;
   
   // Multiplications
   reg             IDR_MUL;
   reg             IDR_MLA;
   reg             IDR_UMULL;
   reg             IDR_UMLAL;
   reg             IDR_SMULL;
   reg             IDR_SMLAL;
   
   //SPSR Move
   reg             IDR_MSR_R;		// Register operand
   reg             IDR_MSR_I;		// Immediate operand
   reg             IDR_MRS;
   
   // Branch
   reg             IDR_B;
   reg             IDR_BL;
   reg             IDR_BX;
   
   // Load
   reg             IDR_LDR;
   reg             IDR_LDRT;
   reg             IDR_LDRB;
   reg             IDR_LDRBT;
   reg             IDR_LDRSB;
   reg             IDR_LDRH;
   reg             IDR_LDRSH;
   
   reg             IDR_LDM;		// ?? Variants
   
   // Store
   reg             IDR_STR;
   reg             IDR_STRT;
   reg             IDR_STRB;
   reg             IDR_STRBT;
   reg             IDR_STRH;
   
   reg             IDR_STM;		// ?? Variants
   
   // Swap
   reg             IDR_SWP;
   reg             IDR_SWPB;
   
   reg             IDR_SWI;
   
   // Coprocessor communication instructions
   reg             IDR_MRC;
   reg             IDR_MCR;
   reg             IDR_LDC;
   reg             IDR_CDP;
   reg             IDR_STC;
   
   // Undefined instruction
   reg             IDR_Undef;
   
   // Thumb branch with link support
   reg             IDR_ThBLFP;		// Can appear only in Thumb mode
   reg             IDR_ThBLSP;		// Can appear only in Thumb mode
   
   // End of registeres instruction decoder outputs
   
   // Instructions groops
   // Arithmetic instructions extension space
   wire            IDC_ArInstExtSp;		// Bit[25](I)='0' and Bit[7](I)='1' and Bit[4](I)='1'
   
   wire            IDC_DPIRegSh;		// Data processing register shift
   wire            IDC_DPIImmSh;		// Data processing immediate shift
   wire            IDC_DPIImmRot;		// Data processing immediate(rotate)
   
   wire            IDC_LSRegOffset;		// Load/store(word/byte) register offset
   wire            IDC_LSImmOffset;		// Load/store(word/byte) immediate offset
   
   wire            IDC_LSHWImmOffset;		// Load/store(halfword) immediate offset
   wire            IDC_LSHWRegOffset;		// Load/store(halfword) register offset
   wire            IDC_LHWBSImmOffset;		// Load signed (halfword/byte) immediate offset
   wire            IDC_LHWBSRegOffset;		// Load signed (halfword/byte) register offset
   
   wire            IDC_LdStInst;		// Load/strore single or multiple
   
   wire            IDC_Branch;
   
   wire            IDC_Compare;
   
   wire            IDC_DPIArith;		// Data processing instructions writing V flag
   
   // Registered signals
   
   reg             IDR_DPIRegSh;
   reg             IDR_DPIImmSh;
   reg             IDR_DPIImmRot;
   
   reg             IDR_LSRegOffset;
   reg             IDR_LSImmOffset;
   
   reg             IDR_LSHWImmOffset;
   reg             IDR_LSHWRegOffset;
   reg             IDR_LHWBSImmOffset;
   reg             IDR_LHWBSRegOffset;
   
   reg             IDR_LdStInst;		// Load/strore single or multiple
   
   reg             IDR_Branch;
   
   reg             IDR_Compare;
   
   reg             IDR_DPIArith;
   
   // Single cycle data processing instruction
   reg             IDR_SingleCycleDPI;
   
   // Instruction state machines (cycle count ??)
   
   // Data processing instruction with shift by Rs (2 cycles - additional cycle for simple DPI)
   reg             DPIRegSh_St;
   
   // Data processing/load instruction writes to PC
   reg             nWrPCSM_St0;
   reg             WrPCSM_St1;
   reg             WrPCSM_St2;
   
   // Load register (3 cycle)
   reg             nLDR_St0;
   reg             LDR_St1;
   reg             LDR_St2;
   
   // Load multiple registers (up to ? cycle)
   reg             nLDM_St0;
   reg             LDM_St1;
   reg             LDM_St2;
   
   // Store register (2 cycle)
   reg             STR_St;
   
   // Load multiple registers (up to ? cycle)
   reg             STM_St;
   
   // Access to User Mode Registers during LDM/STM (special form - ^)
   reg             UMRAccess_St;
   wire            LSMUMR;		// Load/store multiple User Mode Registers
   
   wire            UpDBaseRSng;		// Update base register for single load/store
   
   // TBD
   
   // Multiplications
   
   // MUL
   reg             MUL_St;
   
   // MLA
   reg             nMLA_St0;
   reg             MLA_St1;
   reg             MLA_St2;
   
   // SMULL/UMULL
   reg             nMULL_St0;
   reg             MULL_St1;
   reg             MULL_St2;
   
   // SMLAL/UMLAL
   reg             nMLAL_St0;
   reg             MLAL_St1;
   reg             MLAL_St2;
   reg             MLAL_St3;
   
   reg             BaseRegUdate_St;
   reg             BaseRegWasUdated_St;
   reg [4:0]       LSMCycleCnt;
   reg [4:0]       RegNumCnt[0:15];
   
   reg             LSMStop;
   reg             LSMStopDel;
   
   // Next	register address calculation
   reg [3:0]       CurrentRgAdr;
   wire [3:0]      FirstRgAdr;
   reg [3:0]       NextRgAdr[0:15];
   reg [3:0]       RgAdr[0:15];
   
   // Swap	(4 cycle)
   reg             nSWP_St0;
   reg             SWP_St1;
   reg             SWP_St2;
   reg             SWP_St3;
   
   // Branch (3 cycle)
   reg             nBranch_St0;
   reg             Branch_St1;
   reg             Branch_St2;
   
   reg             BLink;		// Link indicator for branch with link
   
   // Exception state machine
   wire            ExceptSMStart;
   reg             nExceptSM_St0;
   reg             ExceptSM_St1;
   reg             ExceptSM_St2;
   
   wire            ExceptFC;		// The first cycle of exception
   
   // Individual exception start signals
   wire            DAbtExcStart;		// Data abort exception start
   wire            FIQExcStart;		// FIQ exception start
   wire            IRQExcStart;		// IRQ exception start
   wire            PAbtExcStart;		// Prefetch abort exception start
   wire            SWI_UndefExcStart;		// SWI or undefined instruction exception start
   
   // Latched interrupt request
   reg             FIQLatched;
   reg             IRQLatched;
   
   // Various data aborts
   reg             DAbtFlag;
   reg             LSAbtOccurred;
   reg             DAbtStored;
   
   // New CPSR mode
   wire [4:0]      NewMode;
   wire            NewFFlag;
   wire            NewIFlag;
   wire            NewTFlag;
   
   // Pipeline stagnation
   wire            StagnatePipeline_Int;
   
   // StagnatePipeline signal delayed by one clock cycle
   reg             StagnatePipelineDel_Int;
   
   // First instruction fetch after reset
   reg             FirstInstFetch_Int;
   
   // Pipeline refilling
   wire            PipelineRefilling;
   
   // Conditional execution
   wire            ConditionIsTrue;
   
   wire            ExecuteInst;
   
   wire CPSRNFlag = CPSROut[31];
   wire CPSRZFlag = CPSROut[30];
   wire CPSRCFlag = CPSROut[29];
   wire CPSRVFlag = CPSROut[28];
   
   wire CPSRIFlag = CPSROut[7];
   wire CPSRFFlag = CPSROut[6];
   wire CPSRTFlag = CPSROut[5];
   wire [4:0] CPSRMode = CPSROut[4:0];
   
   // CPSR write enable signals
   //alias CPSRNFlWE   : std_logic is CPSRWrEn(31);
   //alias CPSRZFlWE   : std_logic is CPSRWrEn(30);
   //alias CPSRCFlWE   : std_logic is CPSRWrEn(29);
   //alias CPSRVFlWE   : std_logic is CPSRWrEn(28);
   //alias CPSRTFlWE   : std_logic is CPSRWrEn(5);
	
	wire CPSRNFlWE = CPSRWrEn[31];
	wire CPSRZFlWE = CPSRWrEn[30];
	wire CPSRCFlWE = CPSRWrEn[29];
	wire CPSRVFlWE = CPSRWrEn[28];
	wire CPSRTFlWE = CPSRWrEn[5];
   
   wire            CPSRModeWE;		// Permits write to CPSR[4:0]
   
   // Internal signals for the flags which can be generated in different ways
   wire            NewZFlag;
   
   // Register file control signals(internal copies of outputs)
   wire [3:0]      WriteAdr_Int;
   wire            WrEn_Int;
   
   // Additional control signals for ALU and A-Bus multiplexer (for exceptions)
   reg             PassA_Reg;
   reg             PassB_Reg;
   
   reg             RegFileAOutSel_Reg;
   reg             MultiplierAOutSel_Reg;
   reg             CPSROutSel_Reg;
   reg             SPSROutSel_Reg;
   
   reg             ClrBitZero_Reg;
   reg             ClrBitOne_Reg;
   reg             SetBitZero_Reg;
   
   // *******************************************************************************************
   // Instruction decoder
   // *******************************************************************************************
   
   // Arithmetic instruction extension space
   assign IDC_ArInstExtSp = (InstForDecode[25] == 1'b0 & InstForDecode[7] == 1'b1 & InstForDecode[4] == 1'b1);
   
   // Data processing instructions
   
   assign IDC_AND = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0000 & IDC_ArInstExtSp == 1'b0);
   assign IDC_EOR = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0001 & IDC_ArInstExtSp == 1'b0);
   assign IDC_ORR = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b1100 & IDC_ArInstExtSp == 1'b0);
   assign IDC_BIC = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b1110 & IDC_ArInstExtSp == 1'b0);
   assign IDC_ADD = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0100 & IDC_ArInstExtSp == 1'b0);
   assign IDC_ADC = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0101 & IDC_ArInstExtSp == 1'b0);
   assign IDC_SUB = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0010 & IDC_ArInstExtSp == 1'b0);
   assign IDC_SBC = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0110 & IDC_ArInstExtSp == 1'b0);
   assign IDC_RSB = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0011 & IDC_ArInstExtSp == 1'b0);
   assign IDC_RSC = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b0111 & IDC_ArInstExtSp == 1'b0);
   
   // Move
   assign IDC_MOV = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b1101 & IDC_ArInstExtSp == 1'b0);
   assign IDC_MVN = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:21] == 4'b1111 & IDC_ArInstExtSp == 1'b0);
   
   // Instructions which only can change CPSR flags (compare)
   assign IDC_CMP = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:20] == 5'b10101 & IDC_ArInstExtSp == 1'b0);
   assign IDC_CMN = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:20] == 5'b10111 & IDC_ArInstExtSp == 1'b0);
   assign IDC_TST = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:20] == 5'b10001 & IDC_ArInstExtSp == 1'b0);
   assign IDC_TEQ = (InstForDecode[27:26] == 2'b00 & InstForDecode[24:20] == 5'b10011 & IDC_ArInstExtSp == 1'b0);
   
   // End of data processing instructions
   
   // Multiplications
   assign IDC_MUL = (InstForDecode[27:21] == 7'b0000000 & InstForDecode[7:4] == 4'b1001);
   assign IDC_MLA = (InstForDecode[27:21] == 7'b0000001 & InstForDecode[7:4] == 4'b1001);
   assign IDC_UMULL = (InstForDecode[27:21] == 7'b0000100 & InstForDecode[7:4] == 4'b1001);
   assign IDC_UMLAL = (InstForDecode[27:21] == 7'b0000101 & InstForDecode[7:4] == 4'b1001);
   assign IDC_SMULL = (InstForDecode[27:21] == 7'b0000110 & InstForDecode[7:4] == 4'b1001);
   assign IDC_SMLAL = (InstForDecode[27:21] == 7'b0000111 & InstForDecode[7:4] == 4'b1001);
   
   // Move immediate value to status register(CPSR/SPSR)
   // (works like data processing instruction with immediate)
   assign IDC_MSR_I = (InstForDecode[27:23] == 5'b00110 & InstForDecode[21:20] == 2'b10);
   
   // Move register value to status register(CPSR/SPSR)
   // (works like data processing instruction with immediate)
   assign IDC_MSR_R = (InstForDecode[27:23] == 5'b00010 & InstForDecode[21:20] == 2'b10 & InstForDecode[7:4] == 4'b0000);
   
   // Move status register(CPSR/SPSR) to general purpose register
   assign IDC_MRS = (InstForDecode[27:23] == 5'b00010 & InstForDecode[21:20] == 2'b00 & InstForDecode[7:4] == 4'b0000);
   
   // Branch
   assign IDC_B = (InstForDecode[27:24] == 4'b1010); 		// ?? Merge
   assign IDC_BL = (InstForDecode[27:24] == 4'b1011); 		// ?? Merge
   assign IDC_BX = (InstForDecode[27:20] == 8'b00010010 & InstForDecode[7:4] == 4'b0001);
   
   // Load
   assign IDC_LDR = (InstForDecode[27:26] == 2'b01 & InstForDecode[22] == 1'b0 & InstForDecode[20] == 1'b1);
   
   // Load byte !!! TBD
   assign IDC_LDRB = (InstForDecode[27:26] == 2'b01 & InstForDecode[22] == 1'b1 & InstForDecode[20] == 1'b1);
   
   // Load byte with translation !!! TBD
   assign IDC_LDRBT = (InstForDecode[27:26] == 2'b01 & InstForDecode[24] == 1'b0 & InstForDecode[22:20] == 3'b111);
   
   // Load halfword  !!! TBD
   assign IDC_LDRH = (InstForDecode[27:25] == 3'b000 & InstForDecode[20] == 1'b1 & InstForDecode[7:4] == 4'b1011);
   
   // Load signed byte	!!! TBD
   assign IDC_LDRSB = (InstForDecode[27:25] == 3'b000 & InstForDecode[20] == 1'b1 & InstForDecode[7:4] == 4'b1101);
   
   // Load signed halfword	!!! TBD
   assign IDC_LDRSH = (InstForDecode[27:25] == 3'b000 & InstForDecode[20] == 1'b1 & InstForDecode[7:4] == 4'b1111);
   
   // Load word with translation !!! TBD
   assign IDC_LDRT = (InstForDecode[27:26] == 2'b01 & InstForDecode[24] == 1'b0 & InstForDecode[22:20] == 3'b011);
   
   // All the types of load multiple registers
   assign IDC_LDM = (InstForDecode[27:25] == 3'b100 & InstForDecode[20] == 1'b1);
   
   // Store
   assign IDC_STR = (InstForDecode[27:26] == 2'b01 & InstForDecode[22] == 1'b0 & InstForDecode[20] == 1'b0);
   
   // Store byte !!! TBD
   assign IDC_STRB = (InstForDecode[27:26] == 2'b01 & InstForDecode[22] == 1'b1 & InstForDecode[20] == 1'b0);
   
   // Store byte with translation !!! TBD
   assign IDC_STRBT = (InstForDecode[27:26] == 2'b01 & InstForDecode[24] == 1'b0 & InstForDecode[22:20] == 3'b110);
   
   // Store halfword !!! TBD
   assign IDC_STRH = (InstForDecode[27:25] == 3'b000 & InstForDecode[20] == 1'b0 & InstForDecode[7:4] == 4'b1011);
   
   // Store word with translation !!! TBD
   assign IDC_STRT = (InstForDecode[27:26] == 2'b01 & InstForDecode[24] == 1'b0 & InstForDecode[22:20] == 3'b010);
   
   // All the types of store multiple registers
   assign IDC_STM = (InstForDecode[27:25] == 3'b100 & InstForDecode[20] == 1'b0);
   
   // Swap word
   assign IDC_SWP = (InstForDecode[27:20] == 8'b00010000 & InstForDecode[7:4] == 4'b1001);
   // Swap byte
   assign IDC_SWPB = (InstForDecode[27:20] == 8'b00010100 & InstForDecode[7:4] == 4'b1001);
   
   // Software interrupt
   assign IDC_SWI = (InstForDecode[27:24] == 4'b1111);
   
   // Coprocessor instructions
   assign IDC_MRC = (InstForDecode[27:24] == 4'b1110 & InstForDecode[20] == 1'b1 & InstForDecode[4] == 1'b1);
   assign IDC_MCR = (InstForDecode[27:24] == 4'b1110 & InstForDecode[20] == 1'b0 & InstForDecode[4] == 1'b1);
   assign IDC_LDC = (InstForDecode[27:25] == 3'b110 & InstForDecode[20] == 1'b1);
   assign IDC_CDP = (InstForDecode[27:24] == 4'b1110 & InstForDecode[4] == 1'b0);
   assign IDC_STC = (InstForDecode[27:25] == 3'b110 & InstForDecode[20] == 1'b0);
   assign IDC_Undef = (InstForDecode[27:25] == 3'b011 & InstForDecode[4] == 1'b1); 		// TBD
   
   // Instruction groops
   
   // Data processing immediate shift (shift)
   assign IDC_DPIImmSh = (InstForDecode[27:25] == 3'b000 & InstForDecode[4] == 1'b0 & (~(InstForDecode[24:23] == 2'b10 & InstForDecode[20] == 1'b0)));
   
   // Data processing register shift
   assign IDC_DPIRegSh = (InstForDecode[27:25] == 3'b000 & InstForDecode[7] == 1'b0 & InstForDecode[4] == 1'b1 & (~((InstForDecode[24:23] == 2'b10 & InstForDecode[20] == 1'b0) | (InstForDecode[7] == 1'b1 & InstForDecode[4] == 1'b1))));
   
   // Data processing immediate (rotate)
   assign IDC_DPIImmRot = (InstForDecode[27:25] == 3'b001 & (~(InstForDecode[24:23] == 2'b10 & InstForDecode[20] == 1'b0)));
   
   // Load/store register offset(shift)
   assign IDC_LSRegOffset = (InstForDecode[27:25] == 3'b011 & InstForDecode[4] == 1'b0);
   
   // Load/store immediate offset
   assign IDC_LSImmOffset = (InstForDecode[27:25] == 3'b010);
   
   // Load/store(halfword) register offset
   assign IDC_LSHWRegOffset = (InstForDecode[27:25] == 3'b000 & InstForDecode[22] == 1'b0 & InstForDecode[7:4] == 4'b1011);
   
   // Load/store(halfword) immediate offset
   assign IDC_LSHWImmOffset = (InstForDecode[27:25] == 3'b000 & InstForDecode[22] == 1'b1 & InstForDecode[7:4] == 4'b1011);
   
   // Load signed (halfword/byte) register offset
   assign IDC_LHWBSRegOffset = (InstForDecode[27:25] == 3'b000 & InstForDecode[22] == 1'b0 & InstForDecode[20] == 1'b1 & InstForDecode[7:6] == 2'b11 & InstForDecode[4] == 1'b1);
   
   // Load signed (halfword/byte) immediate offset
   assign IDC_LHWBSImmOffset = (InstForDecode[27:25] == 3'b000 & InstForDecode[22] == 1'b1 & InstForDecode[20] == 1'b1 & InstForDecode[7:6] == 2'b11 & InstForDecode[4] == 1'b1);
   
   // All of the load/store(multiple)
   assign IDC_LdStInst = IDC_LDR | IDC_LDRT | IDC_LDRB | IDC_LDRBT | IDC_LDRSB | IDC_LDRH | IDC_LDRSH | IDC_LDM | IDC_STR | IDC_STRT | IDC_STRB | IDC_STRBT | IDC_STRH | IDC_STM;
   
   assign IDC_Branch = IDC_B | IDC_BL | IDC_BX;
   
   assign IDC_Compare = IDC_TST | IDC_TEQ | IDC_CMP | IDC_CMN;
   
   assign IDC_DPIArith = IDC_ADD | IDC_ADC | IDC_SUB | IDC_SBC | IDC_RSB | IDC_RSC | IDC_CMP | IDC_CMN;
   
   // *******************************************************************************************
   // End of the instruction decoder
   // *******************************************************************************************
   
   // Instruction decoder register
   
   always @(negedge nRESET or posedge CLK)
   begin: InstrDecoderRegs
      if (nRESET == 1'b0)		// Reset
      begin
         
         IDR_AND <= 1'b0;
         IDR_EOR <= 1'b0;
         IDR_ORR <= 1'b0;
         IDR_BIC <= 1'b0;
         IDR_TST <= 1'b0;
         IDR_TEQ <= 1'b0;
         IDR_ADD <= 1'b0;
         IDR_ADC <= 1'b0;
         IDR_SUB <= 1'b0;
         IDR_SBC <= 1'b0;
         IDR_RSB <= 1'b0;
         IDR_RSC <= 1'b0;
         IDR_CMP <= 1'b0;
         IDR_CMN <= 1'b0;
         IDR_MOV <= 1'b0;
         IDR_MVN <= 1'b0;
         
         IDR_MUL <= 1'b0;
         IDR_MLA <= 1'b0;
         IDR_UMULL <= 1'b0;
         IDR_UMLAL <= 1'b0;
         IDR_SMULL <= 1'b0;
         IDR_SMLAL <= 1'b0;
         
         IDR_MSR_R <= 1'b0;
         IDR_MSR_I <= 1'b0;
         IDR_MRS <= 1'b0;
         
         IDR_B <= 1'b0;
         IDR_BL <= 1'b0;
         IDR_BX <= 1'b0;
         
         IDR_LDR <= 1'b0;
         IDR_LDRT <= 1'b0;
         IDR_LDRB <= 1'b0;
         IDR_LDRBT <= 1'b0;
         IDR_LDRSB <= 1'b0;
         IDR_LDRH <= 1'b0;
         IDR_LDRSH <= 1'b0;
         
         IDR_LDM <= 1'b0;
         
         IDR_STR <= 1'b0;
         IDR_STRT <= 1'b0;
         IDR_STRB <= 1'b0;
         IDR_STRBT <= 1'b0;
         IDR_STRH <= 1'b0;
         
         IDR_STM <= 1'b0;
         
         IDR_SWP <= 1'b0;
         IDR_SWPB <= 1'b0;
         
         IDR_SWI <= 1'b0;
         
         IDR_MRC <= 1'b0;
         IDR_MCR <= 1'b0;
         IDR_LDC <= 1'b0;
         IDR_CDP <= 1'b0;
         IDR_STC <= 1'b0;
         
         // Thumb branch with link support
         IDR_ThBLFP <= 1'b0;
         IDR_ThBLSP <= 1'b0;
         
         IDR_Undef <= 1'b0;
         
         // Instruction groops
         IDR_DPIRegSh <= 1'b0;
         IDR_DPIImmSh <= 1'b0;
         IDR_DPIImmRot <= 1'b0;
         IDR_LSRegOffset <= 1'b0;
         IDR_LSImmOffset <= 1'b0;
         IDR_LSHWImmOffset <= 1'b0;
         IDR_LSHWRegOffset <= 1'b0;
         IDR_LHWBSImmOffset <= 1'b0;
         IDR_LHWBSRegOffset <= 1'b0;
         IDR_LdStInst <= 1'b0;
         IDR_SingleCycleDPI <= 1'b0;
         IDR_Branch <= 1'b0;
         IDR_Compare <= 1'b0;
         IDR_DPIArith <= 1'b0;
         
         // Stored instruction and it's abort indicator
         InstForDecodeLatched <= 32'h00000000;
         IFAbtStored <= 1'b0;
         
         // External interrupt requests syncronization with instruction execution
         FIQLatched <= 1'b0;
         IRQLatched <= 1'b0;
      end
      
      else 		// Clock
      begin
         if (StagnatePipeline_Int == 1'b0 & CLKEN == 1'b1)		// Clock enable
         begin
            
            IDR_AND <= IDC_AND;
            IDR_EOR <= IDC_EOR;
            IDR_ORR <= IDC_ORR;
            IDR_BIC <= IDC_BIC;
            IDR_TST <= IDC_TST;
            IDR_TEQ <= IDC_TEQ;
            IDR_ADD <= IDC_ADD;
            IDR_ADC <= IDC_ADC;
            IDR_SUB <= IDC_SUB;
            IDR_SBC <= IDC_SBC;
            IDR_RSB <= IDC_RSB;
            IDR_RSC <= IDC_RSC;
            IDR_CMP <= IDC_CMP;
            IDR_CMN <= IDC_CMN;
            IDR_MOV <= IDC_MOV;
            IDR_MVN <= IDC_MVN;
            
            IDR_MUL <= IDC_MUL;
            IDR_MLA <= IDC_MLA;
            IDR_UMULL <= IDC_UMULL;
            IDR_UMLAL <= IDC_UMLAL;
            IDR_SMULL <= IDC_SMULL;
            IDR_SMLAL <= IDC_SMLAL;
            
            IDR_MSR_R <= IDC_MSR_R;
            IDR_MSR_I <= IDC_MSR_I;
            IDR_MRS <= IDC_MRS;
            
            IDR_B <= IDC_B;
            IDR_BL <= IDC_BL;
            IDR_BX <= IDC_BX;
            
            IDR_LDR <= IDC_LDR;
            IDR_LDRT <= IDC_LDRT;
            IDR_LDRB <= IDC_LDRB;
            IDR_LDRBT <= IDC_LDRBT;
            IDR_LDRSB <= IDC_LDRSB;
            IDR_LDRH <= IDC_LDRH;
            IDR_LDRSH <= IDC_LDRSH;
            
            IDR_LDM <= IDC_LDM;
            
            IDR_STR <= IDC_STR;
            IDR_STRT <= IDC_STRT;
            IDR_STRB <= IDC_STRB;
            IDR_STRBT <= IDC_STRBT;
            IDR_STRH <= IDC_STRH;
            
            IDR_STM <= IDC_STM;
            
            IDR_SWP <= IDC_SWP;
            IDR_SWPB <= IDC_SWPB;
            
            IDR_SWI <= IDC_SWI;
            
            IDR_MRC <= IDC_MRC;
            IDR_MCR <= IDC_MCR;
            IDR_LDC <= IDC_LDC;
            IDR_CDP <= IDC_CDP;
            IDR_STC <= IDC_STC;
            
            // Thumb branch with link support
            IDR_ThBLFP <= ThBLFP;
            IDR_ThBLSP <= ThBLSP;
            
            IDR_Undef <= IDC_Undef;
            
            // Instruction groops
            IDR_DPIRegSh <= IDC_DPIRegSh;
            IDR_DPIImmSh <= IDC_DPIImmSh;
            IDR_DPIImmRot <= IDC_DPIImmRot;
            IDR_LSRegOffset <= IDC_LSRegOffset;
            IDR_LSImmOffset <= IDC_LSImmOffset;
            
            IDR_LSHWImmOffset <= IDC_LSHWImmOffset;
            IDR_LSHWRegOffset <= IDC_LSHWRegOffset;
            IDR_LHWBSRegOffset <= IDC_LHWBSRegOffset;
            IDR_LHWBSImmOffset <= IDC_LHWBSImmOffset;
            
            IDR_LdStInst <= IDC_LdStInst;
            
            IDR_SingleCycleDPI <= IDC_DPIImmSh | IDC_DPIImmRot;
            
            IDR_Branch <= IDC_Branch;
            IDR_Compare <= IDC_Compare;
            
            IDR_DPIArith <= IDC_DPIArith;
            
            // Stored instruction and it's abort indicator
            InstForDecodeLatched <= InstForDecode;
            IFAbtStored <= InstFetchAbort;
            
            // External interrupt requests syncronization with instruction execution
            FIQLatched <= (~nFIQ);
            IRQLatched <= (~nIRQ);
         end
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Shifter control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   
   always @(negedge nRESET or posedge CLK)
   begin: ShifterCtrl
      if (nRESET == 1'b0)		// Reset
      begin
         
         ShLenImm <= {5{1'b0}};
         ShType <= {3{1'b0}};
         ShRotImm <= 1'b0;
         ShEn <= 1'b0;
         ShCFlagEn <= 1'b0;
      end
      
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            
            case (StagnatePipeline_Int)
               // Beginning of the new instruction
               1'b0 :
                  
                  if (ExceptFC == 1'b1)		// First cycle of exception
                  begin
                     
                     // CPU in ARM mode
                     if (CPSRTFlag == 1'b0 | DAbtExcStart == 1'b1)		// Data abort
                     begin
                        // Shifter is disabled
                        ShEn <= 1'b0;
                        ShCFlagEn <= 1'b0;
                     end
                     else
                     begin
                        // LSR by 1 (4>>1=2)
                        ShType <= 3'b010;
                        ShRotImm <= 1'b0;
                        ShEn <= 1'b1;
                        ShCFlagEn <= 1'b0;
                        ShLenImm <= 5'b00001;
                     end
                  end
                  else	// No exception

					if (Branch_St1 == 1'b1)
                     begin
                        // LR=LR-4(ARM)/LR=LR-2(Thumb)
                        if (CPSRTFlag == 1'b1)		// Thumb mode
                        begin
                           ShType <= 3'b010;		// LSR by immediate
                           ShRotImm <= 1'b0;
                           ShEn <= 1'b1;
                           ShCFlagEn <= 1'b0;
                           ShLenImm <= 5'b00001;		// Shift right by one
                        end
                        else
                        begin
                           // ARM mode - disable shifter
                           ShEn <= 1'b0;
                           ShCFlagEn <= 1'b0;
                        end
                     end
                     
                     else if (ThBLFP == 1'b1 & CPSRTFlag == 1'b1)
                     begin
                        // Thumb BL the first part LR<=PC+(SignExtend(offset_11)<<12)
                        ShType <= 3'b000;		// LSL by immediate
                        ShRotImm <= 1'b0;
                        ShEn <= 1'b1;
                        ShCFlagEn <= 1'b0;
                        ShLenImm <= 5'b01100;		// Shift amount=12
                     end
                     
                     else if (ThBLSP == 1'b1 & CPSRTFlag == 1'b1)
                     begin
                        // Thumb BL the second part PC<=LR+(SignExtend(offset_11)<<1)|1
                        ShType <= 3'b000;		// LSL by immediate
                        ShRotImm <= 1'b0;
                        ShEn <= 1'b1;
                        ShCFlagEn <= 1'b0;
                        ShLenImm <= 5'b00001;		// Shift amount=1
                     end
                     
                     else if (IDC_B == 1'b1 | (IDC_BL == 1'b1 & CPSRTFlag == 1'b0))
                     begin
                        // Branch or branch with link (destination address calculation)
                        ShType <= 3'b000;		// LSL by immediate
                        ShRotImm <= 1'b0;
                        ShEn <= 1'b1;
                        ShCFlagEn <= 1'b0;
                        // Shift amount depends on mode(ARM/Thumb)
                        if (CPSRTFlag == 1'b0)		// ARM mode
                           ShLenImm <= 5'b00010;
                        else
                           ShLenImm <= 5'b00001;		// Thumb mode
                     end
                     
                     else if ((IDC_SWP | IDC_SWPB) == 1'b1)		// Swap/Swap byte
                     begin
                        ShEn <= 1'b0;		// Disable shifter
                        ShCFlagEn <= 1'b0;
                     end
                     else
                     begin
                        
                        // All other cases: data processing instructions, address calculations
                        ShLenImm <= shift_amount;
                        ShType <= {shift, InstForDecode[4]};
                        ShRotImm <= IDC_DPIImmRot | IDC_MSR_I;		// Data processing immediate or move immediate to status register
                        ShEn <= IDC_DPIImmSh | IDC_DPIImmRot | IDC_DPIRegSh | IDC_LSRegOffset | IDC_MSR_I;
                        ShCFlagEn <= IDC_MOV | IDC_MVN | IDC_TST | IDC_TEQ | IDC_ORR | IDC_EOR | IDC_ORR | IDC_BIC | IDC_LSRegOffset;		// Instructions which produce shifter carry out
                     end
               
               // Changes of data path control within the instruction
               1'b1 :
                  if (LDR_St1 == 1'b1 | LDM_St1 == 1'b1)		// The third cycle of load instruction
                     ShEn <= 1'b0;
               
               default : ;
            endcase
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Multiplier control (combinatorial)
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Start for MUL
   assign LoadRsRm = (IDR_MUL & ExecuteInst & (~MUL_St)) | ((IDR_SMULL | IDR_UMULL) & ExecuteInst & (~nMULL_St0)) | MLA_St1 | MLAL_St1;		// Start for SMULL/UMULL
   // Start for MLA/SMLAL/UMLAL
   
   assign UnsignedMul = IDR_UMULL | IDR_UMLAL;
   assign ReadLH = MULL_St2 | MLAL_St3;		// Read bits 63:32 of Partial Sum/Carry
   
   assign LoadPS = (IDR_MLA & ExecuteInst & (~nMLA_St0)) | ((IDR_SMLAL | IDR_UMLAL) & ExecuteInst & (~nMLAL_St0));		// Load Partial Sum (for accumulation)
   
   assign ClearPSC = ((MUL_St | MLA_St2) & MulResRdy) | MULL_St2 | MLAL_St3;		// Clear Partial Sum/Carry after any multiplication
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // ALU control register	(Only data processing instructions are implemented now)
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   
   always @(negedge nRESET or posedge CLK)
   begin: ALUCtrl
      if (nRESET == 1'b0)		// Reset
      begin
         InvA <= 1'b0;
         InvB <= 1'b0;
         PassA_Reg <= 1'b0;
         PassB_Reg <= 1'b0;
         
         AND_Op <= 1'b0;
         ORR_Op <= 1'b0;
         EOR_Op <= 1'b0;
         
         CFlagUse <= 1'b0;
      end
      
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            
            case (StagnatePipeline_Int)
               1'b0 :
                  
                  if (ExceptFC == 1'b1)		// First cycle of exception
                  begin
                     
                     // Start of any exception when CPU is in ARM mode
                     // Undefined instruction or SWI
                     if (CPSRTFlag == 1'b0 | (SWI_UndefExcStart == 1'b1 & CPSRTFlag == 1'b1))		// CPU is in Thumb mode
                     begin
                        
                        // LR<=LR-4 / LR<=LR-2
                        InvA <= 1'b0;
                        InvB <= 1'b1;
                        PassA_Reg <= 1'b0;
                        PassB_Reg <= 1'b0;
                        AND_Op <= 1'b0;
                        ORR_Op <= 1'b0;
                        EOR_Op <= 1'b0;
                        CFlagUse <= 1'b0;
                     end
                     
                     // Prefetch abort
                     // FIQ
                     // IRQ
                     else if ((PAbtExcStart == 1'b1 | FIQExcStart == 1'b1 | IRQExcStart == 1'b1) & CPSRTFlag == 1'b1)		// CPU is in Thumb mode
                     begin
                        
                        // LR <= LR
                        InvA <= 1'b0;
                        InvB <= 1'b0;
                        PassA_Reg <= 1'b1;
                        PassB_Reg <= 1'b0;
                        AND_Op <= 1'b0;
                        ORR_Op <= 1'b0;
                        EOR_Op <= 1'b0;
                        CFlagUse <= 1'b0;
                     end
                     
                     // Data abort
                     else if (DAbtExcStart == 1'b1 & CPSRTFlag == 1'b1)		// CPU is in Thumb mode
                     begin
                        
                        // LR <= LR+2
                        InvA <= 1'b0;
                        InvB <= 1'b0;
                        PassA_Reg <= 1'b0;
                        PassB_Reg <= 1'b0;
                        AND_Op <= 1'b0;
                        ORR_Op <= 1'b0;
                        EOR_Op <= 1'b0;
                        CFlagUse <= 1'b0;
                     end
                  end
                  else
                     
                     // No exception
                     
                     if (Branch_St1 == 1'b1)
                     begin
                        // LR=LR-4(ARM)/LR=LR-2(Thumb)
                        PassA_Reg <= 1'b0;
                        InvB <= 1'b1;
                     end
                     
                     else if (((IDR_B | IDR_BL | (IDR_ThBLFP & CPSRTFlag)) & ExecuteInst) == 1'b1)
                        // LR=PC
                        PassA_Reg <= 1'b1;
                     
                     else if (IDC_BX == 1'b1)
                     begin
                        // Branch with exchange
                        InvA <= 1'b0;
                        InvB <= 1'b0;
                        PassA_Reg <= 1'b0;
                        PassB_Reg <= 1'b1;		// Rm !!!
                        AND_Op <= 1'b0;
                        ORR_Op <= 1'b0;
                        EOR_Op <= 1'b0;
                        CFlagUse <= 1'b0;
                     end
                     
                     // Load/store memory address calculation (post-indexed mode : ADDR=Rm)
                     // Swap/Swap byte
                     // Instructions which are always post-index
                     else if ((IDC_SWP | IDC_SWPB) == 1'b1 | (IDC_LDRT | IDC_LDRBT | IDC_STRT | IDC_STRBT) == 1'b1 | ((IDC_LDR | IDC_LDRB | IDC_LDRH | IDC_LDRSB | IDC_LDRSH | IDC_LDM | IDC_STR | IDC_STRB | IDC_STRH | IDC_STM) == 1'b1 & P == 1'b0))		// Post-indexed
                     begin
                        
                        InvA <= 1'b0;
                        InvB <= 1'b0;
                        PassA_Reg <= 1'b1;		//
                        PassB_Reg <= 1'b0;
                        AND_Op <= 1'b0;
                        ORR_Op <= 1'b0;
                        EOR_Op <= 1'b0;
                        CFlagUse <= 1'b0;
                     end
                     
                     else if ((IDC_LDR | IDC_LDRB | IDC_LDRH | IDC_LDRSB | IDC_LDRSH | IDC_LDM | IDC_STR | IDC_STRB | IDC_STRH | IDC_STM) == 1'b1 & P == 1'b1)		// Pre-indexed
                     begin
                        // Load/store memory address calculation (pre-indexed mode  ADDR=Rm+/- offset)
                        InvA <= 1'b0;
                        InvB <= (~U);		// U=1 - add, U=0 subtract
                        PassA_Reg <= 1'b0;
                        PassB_Reg <= 1'b0;
                        AND_Op <= 1'b0;
                        ORR_Op <= 1'b0;
                        EOR_Op <= 1'b0;
                        CFlagUse <= 1'b0;
                     end
                     else
                     begin
                        
                        // Data processing instructions with /multiplications and branches/ !!! Check
                        InvA <= IDC_RSB | IDC_RSC;
                        InvB <= IDC_SUB | IDC_SBC | IDC_MVN | IDC_BIC | IDC_CMP;
                        PassA_Reg <= 1'b0;		// !!!!
                        PassB_Reg <= IDC_MOV | IDC_MVN | IDC_MSR_I | IDC_MSR_R;
                        AND_Op <= IDC_TST | IDC_AND | IDC_BIC;
                        ORR_Op <= IDC_ORR;
                        EOR_Op <= IDC_TEQ | IDC_EOR;
                        CFlagUse <= IDC_ADC | IDC_SBC | IDC_RSC;
                     end
               
               1'b1 :
                  // Changes of data path control within the instruction
                  
                  if (((MULL_St1 | MLAL_St2) & MulResRdy) == 1'b1)
                     // The last cycle of long multiplication/accumulation(high part of 64-bit)
                     CFlagUse <= 1'b1;
                  
                  else if (IDR_LdStInst == 1'b1 & (nLDR_St0 == 1'b0 & nLDM_St0 == 1'b0 & STR_St == 1'b0 & STM_St == 1'b0))
                  begin
                     // Base update(second cycle of any load/store)
                     InvB <= (~U_Latched);		// U=1 - add, U=0 subtract
                     PassA_Reg <= 1'b0;
                  end
                  
                  else if (LDR_St1 == 1'b1 | LDM_St1 == 1'b1 | SWP_St1 == 1'b1)		// The second cycle of load instruction
                  begin
                     // Write data from data in register to general purpose register
                     PassA_Reg <= 1'b0;		// !!!!
                     InvB <= 1'b0;
                     PassB_Reg <= 1'b1;
                  end
               
               default :
                  ;
            endcase
      end
   end
   
   assign PassA = (ExceptFC == 1'b1) ? 1'b1 : 		// First cycle of exception (LR<=PC)
                  PassA_Reg;
   assign PassB = (ExceptFC == 1'b1) ? 1'b0 : 
                  PassB_Reg;
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Bus A multiplexer control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   
   always @(negedge nRESET or posedge CLK)
   begin: BusAMUXCtrl
      if (nRESET == 1'b0)		// Reset
      begin
         RegFileAOutSel_Reg <= 1'b0;
         MultiplierAOutSel_Reg <= 1'b0;
         CPSROutSel_Reg <= 1'b0;
         SPSROutSel_Reg <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            
            case (StagnatePipeline_Int)
               // Beginning of the new instruction or pipeline refilling(branch/exception)
               1'b0 :
                  
                  if (((IDR_B | IDR_BL | (IDR_ThBLFP & CPSRTFlag)) & ExecuteInst) | Branch_St1)
                     
                     // Branch (the first and the second cycle)
                     RegFileAOutSel_Reg <= 1'b1;
                  else
                  begin
                     
                     RegFileAOutSel_Reg <= IDC_DPIImmSh | IDC_DPIRegSh | IDC_DPIImmRot | IDC_LSImmOffset | IDC_LSRegOffset | IDC_LSHWImmOffset | IDC_LSHWRegOffset | IDC_LHWBSImmOffset | IDC_LHWBSRegOffset | IDC_LDM | IDC_STM | IDC_Branch | IDC_SWP | IDC_SWPB;		// B/BL/BX
                     // SWP/SWPB
                     
                     MultiplierAOutSel_Reg <= (IDC_MUL | IDC_MLA | IDC_UMULL | IDC_UMLAL | IDC_SMULL | IDC_SMLAL);
                     CPSROutSel_Reg <= IDC_MRS & (~InstForDecode[22]);		// Move CPSR to GPR
                     SPSROutSel_Reg <= IDC_MRS & InstForDecode[22];		// Move SPSR to GPR
                  end
               
               // Changes of data path control within the instruction
               1'b1 : ;
               
               default : ;
            endcase
      end
   end
   
   assign RegFileAOutSel = (ExceptFC == 1'b1) ? 1'b1 : 		// First cycle of exception (LR<=PC)
                           RegFileAOutSel_Reg;
   assign MultiplierAOutSel = (ExceptFC == 1'b1) ? 1'b0 : 
                              MultiplierAOutSel_Reg;
   assign CPSROutSel = (ExceptFC == 1'b1) ? 1'b0 : 
                       CPSROutSel_Reg;
   assign SPSROutSel = (ExceptFC == 1'b1) ? 1'b0 : 
                       SPSROutSel_Reg;
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Bus B multiplexer control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   
   always @(negedge nRESET or posedge CLK)
   begin: BusBMUXCtrl
      if (nRESET == 1'b0)		// Reset
      begin
         
         RegFileBOutSel <= 1'b0;
         MultiplierBOutSel <= 1'b0;
         MemDataRegOutSel <= 1'b0;
         SExtOffset24BitSel <= 1'b0;
         Offset12BitSel <= 1'b0;
         Offset8BitSel <= 1'b0;
         Immediate8BitSel <= 1'b0;
         AdrGenDataSel <= 1'b0;
      end
      
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            
            case (StagnatePipeline_Int)
               // Beginning of the new instruction or pipeline refilling(branch/exception)
               1'b0 :
                  
                  if (ExceptFC == 1'b1 | Branch_St1 == 1'b1)		// TBD??
                  begin
                     // LR correction
                     RegFileBOutSel <= 1'b0;
                     MultiplierBOutSel <= 1'b0;
                     MemDataRegOutSel <= 1'b0;
                     SExtOffset24BitSel <= 1'b0;
                     Offset12BitSel <= 1'b0;
                     Offset8BitSel <= 1'b0;
                     Immediate8BitSel <= 1'b0;
                     AdrGenDataSel <= 1'b1;
                  end
                  else
                  begin
                     
                     RegFileBOutSel <= IDC_DPIImmSh | IDC_DPIRegSh | IDC_LSRegOffset | IDC_LSHWRegOffset | IDC_LHWBSRegOffset | IDC_MSR_R | IDC_BX;		// !!! TBD
                     
                     MultiplierBOutSel <= IDC_MUL | IDC_MLA | IDC_UMULL | IDC_UMLAL | IDC_SMULL | IDC_SMLAL;
                     MemDataRegOutSel <= 1'b0;
                     SExtOffset24BitSel <= IDC_B | IDC_BL;
                     Offset12BitSel <= IDC_LSImmOffset;
                     Offset8BitSel <= IDC_LHWBSImmOffset | IDC_LSHWImmOffset;
                     Immediate8BitSel <= IDC_DPIImmRot | IDC_MSR_I;
                     AdrGenDataSel <= IDC_LDM | IDC_STM;
                  end
               
               // Changes of data path control within the instruction
               1'b1 :
                  
                  if (LDR_St1 == 1'b1 | LDM_St1 == 1'b1)
                  begin
                     // The third cycle of load instruction (write to GPR)
                     RegFileBOutSel <= 1'b0;
                     MultiplierBOutSel <= 1'b0;
                     MemDataRegOutSel <= 1'b1;
                     SExtOffset24BitSel <= 1'b0;
                     Offset12BitSel <= 1'b0;
                     Offset8BitSel <= 1'b0;
                     Immediate8BitSel <= 1'b0;
                     AdrGenDataSel <= 1'b0;
                  end
                  
                  else if ((((IDR_LSRegOffset | IDR_LSHWRegOffset) & (~L_Latched) & (~STR_St)) | (IDR_STM & (~STM_St))) == 1'b1)
                  begin
                     // Store instruction with register offset or store multiple (second cycle - base update)
                     
                     RegFileBOutSel <= 1'b0;
                     MultiplierBOutSel <= 1'b0;
                     MemDataRegOutSel <= 1'b0;
                     SExtOffset24BitSel <= 1'b0;
                     Offset12BitSel <= 1'b0;
                     Offset8BitSel <= 1'b0;
                     Immediate8BitSel <= 1'b0;
                     AdrGenDataSel <= 1'b1;
                  end
               
               default :
                  ;
            endcase
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // -- Bit 0,1 clear/set control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   
   always @(negedge nRESET or posedge CLK)
   begin: ResultBitMask
      if (nRESET == 1'b0)		// Reset
      begin
         ClrBitZero_Reg <= 1'b0;
         ClrBitOne_Reg <= 1'b0;
         SetBitZero_Reg <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            
            case (StagnatePipeline_Int)
               // Beginning of the new instruction or pipeline refilling(branch/exception)
               1'b0 :
                  
                  if (ExceptFC == 1'b1 | Branch_St1 == 1'b1)		// TBD (Thumb BL?)
                  begin
                     ClrBitZero_Reg <= 1'b0;
                     ClrBitOne_Reg <= 1'b0;
                     SetBitZero_Reg <= 1'b0;
                  end
                  else
                  begin
                     // Clears bits[1..0] during address phase of LDM/STM/STR !!! TBD
                     ClrBitZero_Reg <= IDC_STR | IDC_STM | IDC_LDM;
                     ClrBitOne_Reg <= (IDC_STR | IDC_STM | IDC_LDM) & (~(IDR_BL & CPSRTFlag & ExecuteInst));
                     SetBitZero_Reg <= (IDR_BL & CPSRTFlag & ExecuteInst);		// Thumb BL support added(the second part of instruction)
                  end
               
               1'b1 :
                  begin
                     ;
                     // Changes of data path control within the instruction
                     ClrBitZero_Reg <= 1'b0;
                     ClrBitOne_Reg <= 1'b0;
                     SetBitZero_Reg <= 1'b0;
                  end
               
               default :
                  ;
            endcase
      end
   end
   
   assign ClrBitZero = (ExceptFC == 1'b1) ? 1'b0 : 
                       ClrBitZero_Reg;
   assign ClrBitOne = (ExceptFC == 1'b1) ? 1'b0 : 
                      ClrBitOne_Reg;
   assign SetBitZero = (ExceptFC == 1'b1) ? 1'b0 : 
                       SetBitZero_Reg;
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Address multiplexer and incrementer control (combinatorial) !!! TBD
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // TBD
   // LDR last two cycles (merged IS cycle)
   // STR
   // STM last cycle
   //		   (LDM_St1 and LSMStop)or(LDM_St2 and LSMStopDel and not WriteToPC)or  -- LDM last cycle  !!! Modify !!!
   assign PCInSel = LDR_St1 | (LDR_St2 & (~WriteToPC)) | STR_St | (STM_St & LSMStop) | (nLDM_St0 & (LSMStop | (LSMStopDel & (~WriteToPC)))) | SWP_St2 | SWP_St3;		// LDM (merged IS cycle)
   // SWP/SWPB last two cycles (merged IS cycle) ???
   
   // Write to PC
   // First cycle of B,BL,BX
   // First cycle of any load/store
   assign ALUInSel = WriteToPC | ((IDR_Branch | (IDR_ThBLFP & CPSRTFlag)) & ExecuteInst & (~nBranch_St0)) | (IDR_LdStInst & ExecuteInst & (~(STR_St | nLDR_St0 | nLDM_St0 | STM_St))) | ((IDR_SWP | IDR_SWPB) & ExecuteInst & (~nSWP_St0)) | SWP_St1;		// SWP/SWPB (Load)
   // SWP/SWPB (Store)
   
   assign AdrCntEn = (~StagnatePipeline_Int) | IDR_STM | STM_St | IDR_LDM | nLDM_St0;		// Address counter is enabled during load/store multiple
   
   assign ExceptionVectorSel = ExceptFC;		// First cycle of exception handling
   
   // TBD  '0'- ARM(+4) / '1'- Thumb(+2)
   assign PCIncStep = (CPSRTFlag | (IDR_BX & RmBitZero & ((~CPSRTFlag))));
   // TBD  '0'- ARM(+4) or STM/LDM / '1'- Thumb(+2)
   // THUMB & ~(Transfer to ARM)
   assign AdrIncStep = ((CPSRTFlag & ((~(IDR_BX & ((~RmBitZero)) & ((~Branch_St1)) & ((~Branch_St2)))))) | (IDR_BX & RmBitZero)) & ((~(IDR_STM & StagnatePipeline_Int & ExecuteInst))) & ((~(IDR_LDM & StagnatePipeline_Int & ExecuteInst)));		// Transfer to THUMB
   
   // Switch ADDR register to the input of PC
   // First cycle of interrupt entering
   assign AdrToPCSel = ExceptFC | Branch_St1;		// Second cycle of branch
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Register file control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Combinatorial rgister address control (controled from the execution stage of the pipeline)!!! TBD !!!
   assign ABusRdAdr = (((IDR_B | IDR_BL | (IDR_ThBLFP & CPSRTFlag)) & ExecuteInst) == 1'b1 | Branch_St1 == 1'b1 | ExceptFC == 1'b1) ? CR_PC : 		// *
                      (Branch_St2 == 1'b1 | ExceptSM_St1 == 1'b1) ? CR_LR : 		// LR correction (BL/Exception)
                      ((IDR_DPIRegSh == 1'b1 & DPIRegSh_St == 1'b0) | (IDR_MUL | IDR_SMULL | IDR_UMULL | nMLA_St0 | nMLAL_St0) == 1'b1) ? Rs : 		// Rs ( The first cycle of "Data processing register shift")
                      Rn;		// Rn
   
   // * Note PC(R15) (target address calculation for B/BL) or store PC to LR (BL/Exception)
   // Thumb BL support added (the first part)
   
   assign BBusRdAdr = (STM_St == 1'b1) ? CurrentRgAdr : 		// Store multiple
                      (((IDR_MLA & (~nMLA_St0)) | ((IDR_UMLAL | IDR_SMLAL) & (~nMLAL_St0))) == 1'b1 | STR_St == 1'b1) ? RnM : 		// Rn/RdLo only for accumulation (MLA/SMLAL/UMLAL), Rd - for STR
                      Rm;		// Rm
   
   assign WriteAdr_Int = (LDM_St2 == 1'b1) ? CurrentRgAdr : 		// Load multiple
                         (nBranch_St0 == 1'b1 | ExceptFC == 1'b1 | ExceptSM_St1 == 1'b1 | (IDR_ThBLFP == 1'b1 & CPSRTFlag == 1'b1 & ExecuteInst == 1'b1)) ? CR_LR : 		// *
                         ((MUL_St | MLA_St2 | MULL_St2 | MLAL_St3) == 1'b1 | (LDM_St1 | STM_St | LDR_St1 | STR_St) == 1'b1) ? RdM : 		// Rd for	32-bit/RdHi for 64-bit multiplications / Base Register for LDM/STM
                         ((MULL_St1 | MLAL_St2) == 1'b1) ? RnM : 		// RdLo for 64-bit multiplications
                         Rd;		// Rd
   
   // * Note: 	   !!! check if presence of nExceptSM_St0='0' is necessary for this equation
   //                       Branch                     Exception
   // Store  LR		   Second cycle					First cycle
   // Modify LR		   Third cycle                  Second cycle
   //
   // Thumb BL support added (the first part)
   
   // Write enable for the general purpose register file
   // Multiplications results
   // Move PSR to GPR
   // Exception : LR<=PC, LR correction
   // BL : LR<=PC, LR correction
   //  Base register update for load/store
   // LDR
   // LDM
   assign WrEn_Int = ((((IDR_SingleCycleDPI & ExecuteInst) | DPIRegSh_St) & (~IDR_Compare)) == 1'b1 | ((((MUL_St | MLA_St2 | MULL_St1 | MLAL_St2) & MulResRdy) | MULL_St2 | MLAL_St3)) == 1'b1 | (IDR_MRS & ExecuteInst) == 1'b1 | (ExceptFC | ExceptSM_St1) == 1'b1 | BLink == 1'b1 | (BaseRegUdate_St == 1'b1 & ABORT == 1'b0) | (LDR_St2 == 1'b1 & DAbtStored == 1'b0) | (LDM_St2 == 1'b1 & DAbtStored == 1'b0 & LSAbtOccurred == 1'b0) | SWP_St2 == 1'b1) ? 1'b1 : 		// SWP/SWPB
                     1'b0;
   
   // PC control
   assign PCSrcSel = WriteToPC;		// 0 -> the incrementer, 1 -> external input bus !!! TBD
   // First instruction fetch after reset
   // Stop PC for multicycle instructions ??? TBD
   // First cycle of branch with link (ARM mode) TBD??
   assign PCWrEn = (FirstInstFetch_Int == 1'b0 | StagnatePipelineDel_Int == 1'b1 | (IDR_BL == 1'b1 & ExecuteInst == 1'b1) | (IDR_ThBLSP == 1'b1 & CPSRTFlag == 1'b1 & ExecuteInst == 1'b1)) ? 1'b0 : 		// First cycle of branch with link (Thumb mode) TBD??
                   1'b1;
   
   // Base register save/restore for load/store multiple
   assign SaveBaseReg = BaseRegUdate_St;
   assign RestoreBaseReg = ((LDM_St2 & LSMStopDel) | (STM_St & LSMStop)) & LSAbtOccurred & BaseRegWasUdated_St;
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Address generator for Load/Store instructions control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Load/Store multiple registers(LDM/STM) start address and base register update calculation TBD
   assign RegisterList = InstForDecode[15:0];
   //  Selects 4 for : Load/store
   // Start of exceptions (for LR correction)
   assign IncBeforeSel = ((U == 1'b1 & P == 1'b1) | ExceptFC == 1'b1 | Branch_St1 == 1'b1) ? 1'b1 : 		// Branch with link (for LR correction)
                         1'b0;
   
   assign DecBeforeSel = (U == 1'b0 & P == 1'b1) ? 1'b1 : 
                         1'b0;
   assign DecAfterSel = (U == 1'b0 & P == 1'b0) ? 1'b1 : 
                        1'b0;
   assign MltAdrSel = (IDR_LDM | IDR_STM) & ExecuteInst;		// Base register update for LDM/STM
   assign SngMltSel = (IDR_LDR | IDR_LDRT | IDR_LDRB | IDR_LDRBT | IDR_LDRSB | IDR_LDRH | IDR_LDRSH | IDR_STR | IDR_STRT | IDR_STRB | IDR_STRBT | IDR_STRH) & ExecuteInst & ((~IDC_STM));		// ??? TBD '0' -> LDM/STM and LR corrections
   
   // Notes:
   // IncBeforeSel has the highest priority
   // DecAfterSel  has the lowest priority
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Instruction pipeline and data in registers control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Pipeline stagnation control for multicycle instructions
   // All the instructions that stagnates pipeline - all there cycles except last one

   assign StagnatePipeline_Int = (((IDR_DPIRegSh & (~DPIRegSh_St)) | 
								 ((IDR_STR | IDR_STRT | IDR_STRB | IDR_STRBT | IDR_STRH) & (~STR_St)) | 
								 ((IDR_LDR | IDR_LDRT | IDR_LDRB | IDR_LDRBT | IDR_LDRSB | IDR_LDRH | IDR_LDRSH) & (~nLDR_St0)) | 
								 (IDR_STM & (~STM_St)) | 
								 (IDR_LDM & (~nLDM_St0)) | 
								 ((IDR_SWP | IDR_SWPB) & (~nSWP_St0)) | 
								 (IDR_MUL & (~MUL_St)) | (IDR_MLA & (~nMLA_St0)) |
								 ((IDR_UMULL | IDR_SMULL) & (~nMULL_St0)) | 
								 ((IDR_UMLAL | IDR_SMLAL) & (~nMLAL_St0))) & 
								 ExecuteInst) | 
								 (LDR_St1 |    										// LDR
								 (STM_St & (~LSMStop)) | 							// STM Check???
								 (LDM_St1 | (LDM_St2 & (~LSMStopDel))) | 			// LDM	Check???
								 SWP_St1 | SWP_St2 | 								// SWAP/SWAPB
								 ((MUL_St | MLA_St2) & (~MulResRdy)) | MLA_St1 | 	// MUL/MLA
								 MULL_St1 | MLAL_St1 | MLAL_St2);					// SMULL/UMULL/SMLAL/UMLAL
   // TBD Other cycles should be included
   
   
   always @(negedge nRESET or posedge CLK)
   begin: PipelineStagnateDelayed
      if (nRESET == 1'b0)		// Reset
         StagnatePipelineDel_Int <= 1'b0;
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            StagnatePipelineDel_Int <= StagnatePipeline_Int;
      end
   end
   
   // Fetch of the first instruction after reset
   
   always @(negedge nRESET or posedge CLK)
   begin: FirstInstructionFetch
      if (nRESET == 1'b0)		// Reset
         FirstInstFetch_Int <= 1'b0;
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            FirstInstFetch_Int <= 1'b1;
      end
   end
   
   // Data in register and control(sign/zero, byte/halfword  extension)
   
   always @(negedge nRESET or posedge CLK)
   begin: DInRegCtrl
      if (nRESET == 1'b0)		// Reset
      begin
         SignExt <= 1'b0;
         ZeroExt <= 1'b0;
         nB_HW <= 1'b0;
      end
      else 		// Clock
      begin
         if (StagnatePipeline_Int == 1'b0 & CLKEN == 1'b1)		// Clock enable
         begin
            SignExt <= IDC_LDRSB | IDC_LDRSH;
            ZeroExt <= IDC_LDRB | IDC_LDRBT | IDC_LDRH | IDC_SWPB;
            nB_HW <= IDC_LDRH | IDC_LDRSH;
         end
      end
   end
   
   // Bus control
   assign EndianMode = 1'b0;		// Little endian (default)
   
   // Global endianness control!!!TBD!!!
   assign BigEndianMode = 1'b0;
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Data output multiplexer control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   
   always @(negedge nRESET or posedge CLK)
   begin: DOutMuxCtrl
      if (nRESET == 1'b0)		// Reset
      begin
         StoreHalfWord <= 1'b0;
         StoreByte <= 1'b0;
      end
      else 		// Clock
      begin
         if (StagnatePipeline_Int == 1'b0 & CLKEN == 1'b1)		// Clock enable
         begin
            StoreHalfWord <= IDC_STRH;
            StoreByte <= IDC_STRB | IDC_STRBT | IDC_SWPB;
         end
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Conditional execution control
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   assign ConditionIsTrue = (cond == 4'b0000 & CPSRZFlag == 1'b1) |									// EQ
							(cond == 4'b0001 & CPSRZFlag == 1'b0) |									// NE
							(cond == 4'b0010 & CPSRCFlag == 1'b1) |									// CS/HS
							(cond == 4'b0011 & CPSRCFlag == 1'b0) |									// CC/LO
							(cond == 4'b0100 & CPSRNFlag == 1'b1) |									// MI
							(cond == 4'b0101 & CPSRNFlag == 1'b0) |									// PL
							(cond == 4'b0110 & CPSRVFlag == 1'b1) |									// VS
							(cond == 4'b0111 & CPSRVFlag == 1'b0) |									// VC
							(cond == 4'b1000 & CPSRCFlag == 1'b1 & CPSRZFlag == 1'b0) |				// HI
							(cond == 4'b1001 & (CPSRCFlag == 1'b0 | CPSRZFlag == 1'b1)) |			// LS
							(cond == 4'b1010 & CPSRNFlag == CPSRVFlag) |							// GE
							(cond == 4'b1011 & CPSRNFlag != CPSRVFlag) |							// LT
							(cond == 4'b1100 & CPSRZFlag == 1'b0 & CPSRNFlag == CPSRVFlag) |		// GT
							(cond == 4'b1101 & (CPSRZFlag == 1'b1 | (CPSRNFlag != CPSRVFlag))) |	// LE
							cond == 4'b1110;														// AL
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Exception handling
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Data abort exception start -> the highest priority
   assign DAbtExcStart = DAbtFlag;
   
   // FIQ exception start
   assign FIQExcStart = (FIQLatched & (~CPSRFFlag)) & (~DAbtExcStart);
   
   // IRQ exception start
   assign IRQExcStart = (IRQLatched & (~CPSRIFlag)) & (~(DAbtExcStart | FIQExcStart));
   
   // Prefetch abort exception start
   assign PAbtExcStart = (IFAbtStored & ConditionIsTrue) & (~(DAbtExcStart | FIQExcStart | IRQExcStart));
   
   // SWI or undefined instruction exception start	 -> the lowest priority
   assign SWI_UndefExcStart = ((IDR_Undef | IDR_SWI) & ConditionIsTrue) & (~(DAbtExcStart | FIQExcStart | IRQExcStart | PAbtExcStart));
   
   // The first cycle of exception
   assign ExceptFC = ExceptSMStart & (~PipelineRefilling);
   
   
   always @(negedge nRESET or posedge CLK)
   begin: AbortForData
      if (nRESET == 1'b0)		// Reset
      begin
         LSAbtOccurred <= 1'b0;
         DAbtStored <= 1'b0;
         DAbtFlag <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            LSAbtOccurred <= ((~LSAbtOccurred) & (		// Set
			(LDR_St1 & ABORT) | 						// Data abort during LDR
			(LDM_St1 & ABORT) | 						// Data abort during LDM(first load)
			(LDM_St2 & (~LSMStopDel) & ABORT) | 		// Data abort during LDM(except fist and last)
			((SWP_St1 | SWP_St2) & ABORT) | 			// Data abort during SWP/SWPB
			(STM_St & (~LSMStop) & ABORT))) | 			// Data abort during STM(except last)
			(LSAbtOccurred & StagnatePipeline_Int);		// Clear : end of instruction*
            
            DAbtFlag <= (~DAbtFlag) & 
			(~StagnatePipeline_Int) & 
			(LSAbtOccurred | ((STR_St | STM_St) & ABORT));
            
            DAbtStored <= ABORT;
         end
      end
   end
   
   // * Note: as far as PC writing is impossible after data abort there is no need to include
   // "write to PC recognition" in this equation
   
   // Exception address generator for exceptions
   assign ExceptionVector = (DAbtFlag == 1'b1) ? CExcAdrDtAbt : 		// Data abort (highest priority)
                            ((FIQLatched & (~CPSRFFlag)) == 1'b1) ? CExcAdrFIQ : 		// Fast interrupt
                            ((IRQLatched & (~CPSRIFlag)) == 1'b1) ? CExcAdrIRQ : 		// Normal interrupt
                            (IFAbtStored == 1'b1) ? CExcAdrPrfAbt : 		// Prefetch abort
                            (IDR_Undef == 1'b1) ? CExcAdrUndefined : 		// Undefined instruction (lowest priority)*
                            (IDR_SWI == 1'b1) ? CExcAdrSWI : 		// Software interrupt(lowest priority)*
                            32'h00000000;
   
   // New mode generator for exceptions
   assign NewMode = (DAbtFlag == 1'b1) ? CAbortMode : 		// Data abort address(highest priority)
                    ((FIQLatched & (~CPSRFFlag)) == 1'b1) ? CFIQMode : 		// Fast interrupt
                    ((IRQLatched & (~CPSRIFlag)) == 1'b1) ? CIRQMode : 		// Normal interrupt
                    (IFAbtStored == 1'b1) ? CAbortMode : 		// Prefetch abort
                    (IDR_Undef == 1'b1) ? CUndefMode : 		// Undefined instruction (lowest priority)*
                    (IDR_SWI == 1'b1) ? CSVCMode : 		// Software interrupt(lowest priority)*
                    5'b00000;
   
   // * Note: These two exceptions are mutually exclusive so they have an equal priority
   
   // Mode for register file control ??? TBD !!!
   assign RFMode = (ExceptFC == 1'b1) ? NewMode : 		// First cycle of the exception
                   (UMRAccess_St == 1'b1) ? CUserMode : 		// User mode registers read/write
                   CPSRMode;		// TBD
   
  // Start of exception state machine (TBD)
   assign ExceptSMStart = ((IDR_Undef | IDR_SWI | IFAbtStored) & ConditionIsTrue) | 	// Undefined instruction/software interrupt/instruction prefetch abort
							DAbtFlag | 													// Data abort
							(FIQLatched & (~CPSRFFlag)) | (IRQLatched & (~CPSRIFlag));	// External interrupts
   
   always @(negedge nRESET or posedge CLK)
   begin: ExceptionStateMachine
      if (nRESET == 1'b0)		// Reset
      begin
         nExceptSM_St0 <= 1'b0;
         ExceptSM_St1 <= 1'b0;
         ExceptSM_St2 <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            
            nExceptSM_St0 <= ((~nExceptSM_St0) & ExceptSMStart & (~(nWrPCSM_St0 | nBranch_St0))) | (nExceptSM_St0 & (~ExceptSM_St2));
            ExceptSM_St1 <= (~ExceptSM_St1) & (~nExceptSM_St0) & ExceptSMStart & (~(nWrPCSM_St0 | nBranch_St0));
            ExceptSM_St2 <= ExceptSM_St1;
         end
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Instruction state machines
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   assign PipelineRefilling = nBranch_St0 | nWrPCSM_St0 | nExceptSM_St0;
   
   //PipelineRefilingDFF:process(nRESET,CLK)
   //begin
   //if nRESET='0' then                -- Reset
   // PipelineRefilling <= '0';
   //elsif CLK='1' and CLK'event then  -- Clock
   // if CLKEN='1' then                -- Clock enable
   //  PipelineRefilling <= (not PipelineRefilling and(
   //                       (not nExceptSM_St0 and ExceptSMStart)or
   //  					   (nBranch_St0 and((IDR_Branch or (IDR_ThBLSP and CPSRTFlag)) and ExecuteInst))or
   //					   (not nWrPCSM_St0 and WriteToPC)))or
   //                       (PipelineRefilling and not(Branch_St2 or ExceptSM_St2 or WrPCSM_St2));
   // end if;
   //end if;
   //end process;
   
   assign ExecuteInst = ConditionIsTrue & (~(ExceptSMStart | PipelineRefilling));		// Instruction must be executed
   
   // Data processing instructions which take two cycles(with register shift)
   always @(negedge nRESET or posedge CLK)
   begin: DPIShiftByReg
      if (nRESET == 1'b0)		// Reset
         DPIRegSh_St <= 1'b0;
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            DPIRegSh_St <= (~DPIRegSh_St) & IDR_DPIRegSh & ExecuteInst;
      end
   end
   
   // Branch state machine (B,BL,BX)- TBD 3 cycle
   always @(negedge nRESET or posedge CLK)
   begin: BranchSM
      if (nRESET == 1'b0)		// Reset
      begin
         nBranch_St0 <= 1'b0;
         Branch_St1 <= 1'b0;
         Branch_St2 <= 1'b0;
      end
      
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            nBranch_St0 <= ((~nBranch_St0) & ((IDR_Branch | (IDR_ThBLSP & CPSRTFlag)) & ExecuteInst)) | (nBranch_St0 & (~Branch_St2));		// Thumb BL support added(the second part of instruction)
            
            Branch_St1 <= (~Branch_St1) & (~nBranch_St0) & ((IDR_Branch | (IDR_ThBLSP & CPSRTFlag)) & ExecuteInst);		// Thumb support is added
            
            Branch_St2 <= Branch_St1;
         end
      end
   end
   
   // Link bit for branch instruction !!! TBD
   always @(negedge nRESET or posedge CLK)
   begin: LinkBitStore
      if (nRESET == 1'b0)		// Reset
         BLink <= 1'b0;
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            BLink <= ((~BLink) & IDR_BL & ExecuteInst) | (BLink & (~Branch_St2));		// Thumb BL support added(the second part of instruction)
      end
   end
   
   // Swap (word/byte)  4 cycles
   always @(negedge nRESET or posedge CLK)
   begin: SwapSM
      if (nRESET == 1'b0)		// Reset
      begin
         
         nSWP_St0 <= 1'b0;
         SWP_St1 <= 1'b0;
         SWP_St2 <= 1'b0;
         SWP_St3 <= 1'b0;
      end
      
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            
            nSWP_St0 <= ((~nSWP_St0) & (IDR_SWP | IDR_SWPB) & ExecuteInst) | (nSWP_St0 & (~SWP_St3));
            
            SWP_St1 <= (~SWP_St1) & (~nSWP_St0) & (IDR_SWP | IDR_SWPB) & ExecuteInst;
            
            SWP_St2 <= SWP_St1;
            
            SWP_St3 <= SWP_St2;
         end
      end
   end
   
   // STR 2 cycles
   always @(negedge nRESET or posedge CLK)
   begin: StoreOneRegister
      if (nRESET == 1'b0)		// Reset
         STR_St <= 1'b0;
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            STR_St <= (~STR_St) & (IDR_STR | IDR_STRT | IDR_STRB | IDR_STRBT | IDR_STRH) & ExecuteInst;		// TBD
      end
   end
   
   // LDR 3 cycles
   always @(negedge nRESET or posedge CLK)
   begin: LoadOneRegister
      if (nRESET == 1'b0)		// Reset
      begin
         nLDR_St0 <= 1'b0;
         LDR_St1 <= 1'b0;
         LDR_St2 <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            nLDR_St0 <= ((~nLDR_St0) & (IDR_LDR | IDR_LDRT | IDR_LDRB | IDR_LDRBT | IDR_LDRSB | IDR_LDRH | IDR_LDRSH) & ExecuteInst) | (nLDR_St0 & (~LDR_St2));
            
            LDR_St1 <= (~LDR_St1) & (~nLDR_St0) & (IDR_LDR | IDR_LDRT | IDR_LDRB | IDR_LDRBT | IDR_LDRSB | IDR_LDRH | IDR_LDRSH) & ExecuteInst;
            
            LDR_St2 <= LDR_St1;
         end
      end
   end
   
   // Load/Store multiple (LDM/STM) cycle counter
   always @(negedge nRESET or posedge CLK)
   begin: LoadStoreMultipleCnt
      if (nRESET == 1'b0)		// Reset
      begin
         LSMCycleCnt <= 5'b00000;
         LSMStop <= 1'b0;
         LSMStopDel <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            if (StagnatePipeline_Int == 1'b0)		//or (IDR_LDM='1' and nLDM_St0='0') then
               LSMCycleCnt <= 5'b00001;		// Clear
            else
               LSMCycleCnt <= LSMCycleCnt + 1;
            if (LSMCycleCnt == RegNumCnt[15])
               LSMStop <= 1'b1;
            else
               LSMStop <= 1'b0;
            
            LSMStopDel <= ((~LSMStopDel) & LSMStop & nLDM_St0);		// LSMStopDel is used in LDM only
         end
      end
   end
   

   // Calculate number of registers to load or to store
   always @(*) RegNumCnt[0] = (InstForDecodeLatched[0] == 1'b1) ? 5'b00001 : 5'b00000;
   generate
      begin : xhdl0
         genvar          i;
         for (i = 1; i <= 15; i = i + 1)
         begin : MultRegNumCounter
            always @(*) RegNumCnt[i] = (InstForDecodeLatched[i] == 1'b1) ? RegNumCnt[i - 1] + 1 : RegNumCnt[i - 1];
         end
      end
   endgenerate

  
  /*
	always @(*) begin
		RegNumCnt[0]  <= (InstForDecodeLatched[0] == 1'b1) ? 5'b00001 : 5'b00000;
		
		RegNumCnt[1]  <= (InstForDecodeLatched[1] == 1'b1)  ? RegNumCnt[0] + 1  : RegNumCnt[0];
		RegNumCnt[2]  <= (InstForDecodeLatched[2] == 1'b1)  ? RegNumCnt[1] + 1  : RegNumCnt[1];
		RegNumCnt[3]  <= (InstForDecodeLatched[3] == 1'b1)  ? RegNumCnt[2] + 1  : RegNumCnt[2];
		RegNumCnt[4]  <= (InstForDecodeLatched[4] == 1'b1)  ? RegNumCnt[3] + 1  : RegNumCnt[3];
		RegNumCnt[5]  <= (InstForDecodeLatched[5] == 1'b1)  ? RegNumCnt[4] + 1  : RegNumCnt[4];
		RegNumCnt[6]  <= (InstForDecodeLatched[6] == 1'b1)  ? RegNumCnt[5] + 1  : RegNumCnt[5];
		RegNumCnt[7]  <= (InstForDecodeLatched[7] == 1'b1)  ? RegNumCnt[6] + 1  : RegNumCnt[6];
		RegNumCnt[8]  <= (InstForDecodeLatched[8] == 1'b1)  ? RegNumCnt[7] + 1  : RegNumCnt[7];
		RegNumCnt[9]  <= (InstForDecodeLatched[9] == 1'b1)  ? RegNumCnt[8] + 1  : RegNumCnt[8];
		RegNumCnt[10] <= (InstForDecodeLatched[10] == 1'b1) ? RegNumCnt[9] + 1  : RegNumCnt[9];
		RegNumCnt[11] <= (InstForDecodeLatched[11] == 1'b1) ? RegNumCnt[10] + 1 : RegNumCnt[10];
		RegNumCnt[12] <= (InstForDecodeLatched[12] == 1'b1) ? RegNumCnt[11] + 1 : RegNumCnt[11];
		RegNumCnt[13] <= (InstForDecodeLatched[13] == 1'b1) ? RegNumCnt[12] + 1 : RegNumCnt[12];
		RegNumCnt[14] <= (InstForDecodeLatched[14] == 1'b1) ? RegNumCnt[13] + 1 : RegNumCnt[13];
		RegNumCnt[15] <= (InstForDecodeLatched[15] == 1'b1) ? RegNumCnt[14] + 1 : RegNumCnt[14];
	end
*/
   
   always @(negedge nRESET or posedge CLK)
   begin: LSMRegAdr
      if (nRESET == 1'b0)		// Reset
         CurrentRgAdr <= {4{1'b0}};
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            if ((IDR_STM == 1'b1 & STM_St == 1'b0) | LDM_St1 == 1'b1)
               CurrentRgAdr <= FirstRgAdr;		// Load first address
            else
               CurrentRgAdr <= NextRgAdr[15];		// Calculate next address
         end
      end
   end
   
   // Calculate address of the next register for load/store multiple
   assign FirstRgAdr = (InstForDecodeLatched[0] == 1'b1) ? 4'b0000 : 
                       (InstForDecodeLatched[1] == 1'b1) ? 4'b0001 : 
                       (InstForDecodeLatched[2] == 1'b1) ? 4'b0010 : 
                       (InstForDecodeLatched[3] == 1'b1) ? 4'b0011 : 
                       (InstForDecodeLatched[4] == 1'b1) ? 4'b0100 : 
                       (InstForDecodeLatched[5] == 1'b1) ? 4'b0101 : 
                       (InstForDecodeLatched[6] == 1'b1) ? 4'b0110 : 
                       (InstForDecodeLatched[7] == 1'b1) ? 4'b0111 : 
                       (InstForDecodeLatched[8] == 1'b1) ? 4'b1000 : 
                       (InstForDecodeLatched[9] == 1'b1) ? 4'b1001 : 
                       (InstForDecodeLatched[10] == 1'b1) ? 4'b1010 : 
                       (InstForDecodeLatched[11] == 1'b1) ? 4'b1011 : 
                       (InstForDecodeLatched[12] == 1'b1) ? 4'b1100 : 
                       (InstForDecodeLatched[13] == 1'b1) ? 4'b1101 : 
                       (InstForDecodeLatched[14] == 1'b1) ? 4'b1110 : 
                       (InstForDecodeLatched[15] == 1'b1) ? 4'b1111 : 
                       4'b0000;
   

   always @(*) NextRgAdr[0] = 4'b0000;
   always @(*) RgAdr[0] = 4'b0000;
   generate
      begin : xhdl1
         genvar          i;
         for (i = 1; i <= 15; i = i + 1)
         begin : NextRegAdrGen
            always @(*) RgAdr[i] = RgAdr[i - 1] + 1;
            always @(*) NextRgAdr[i] = (InstForDecodeLatched[i] == 1'b1 & i > CurrentRgAdr & NextRgAdr[i - 1] == 4'b0000) ? RgAdr[i] : NextRgAdr[i - 1];
         end
      end
   endgenerate

   /*
	// ElectronAsh.
	always @(*) begin
		RgAdr[0] <= 4'b0000;
		RgAdr[1]  <= RgAdr[0] + 1;
		RgAdr[2]  <= RgAdr[1] + 1;
		RgAdr[3]  <= RgAdr[2] + 1;
		RgAdr[4]  <= RgAdr[3] + 1;
		RgAdr[5]  <= RgAdr[4] + 1;
		RgAdr[6]  <= RgAdr[5] + 1;
		RgAdr[7]  <= RgAdr[6] + 1;
		RgAdr[8]  <= RgAdr[7] + 1;
		RgAdr[9]  <= RgAdr[8] + 1;
		RgAdr[10] <= RgAdr[9] + 1;
		RgAdr[11] <= RgAdr[10] + 1;
		RgAdr[12] <= RgAdr[11] + 1;
		RgAdr[13] <= RgAdr[12] + 1;
		RgAdr[14] <= RgAdr[13] + 1;
		RgAdr[15] <= RgAdr[14] + 1;
   
		NextRgAdr[0]  <= 4'b0000;
		NextRgAdr[1]  <= (InstForDecodeLatched[1] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[0]  == 4'b0000) ? RgAdr[1]  : NextRgAdr[0];
		NextRgAdr[2]  <= (InstForDecodeLatched[2] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[1]  == 4'b0000) ? RgAdr[2]  : NextRgAdr[1];
		NextRgAdr[3]  <= (InstForDecodeLatched[3] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[2]  == 4'b0000) ? RgAdr[3]  : NextRgAdr[2];
		NextRgAdr[4]  <= (InstForDecodeLatched[4] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[3]  == 4'b0000) ? RgAdr[4]  : NextRgAdr[3];
		NextRgAdr[5]  <= (InstForDecodeLatched[5] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[4]  == 4'b0000) ? RgAdr[5]  : NextRgAdr[4];
		NextRgAdr[6]  <= (InstForDecodeLatched[6] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[5]  == 4'b0000) ? RgAdr[6]  : NextRgAdr[5];
		NextRgAdr[7]  <= (InstForDecodeLatched[7] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[6]  == 4'b0000) ? RgAdr[7]  : NextRgAdr[6];
		NextRgAdr[8]  <= (InstForDecodeLatched[8] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[7]  == 4'b0000) ? RgAdr[8]  : NextRgAdr[7];
		NextRgAdr[9]  <= (InstForDecodeLatched[9] == 1'b1  & 1 > CurrentRgAdr & NextRgAdr[8]  == 4'b0000) ? RgAdr[9]  : NextRgAdr[8];
		NextRgAdr[10] <= (InstForDecodeLatched[10] == 1'b1 & 1 > CurrentRgAdr & NextRgAdr[9]  == 4'b0000) ? RgAdr[10] : NextRgAdr[9];
        NextRgAdr[11] <= (InstForDecodeLatched[11] == 1'b1 & 1 > CurrentRgAdr & NextRgAdr[10] == 4'b0000) ? RgAdr[11] : NextRgAdr[10];
		NextRgAdr[12] <= (InstForDecodeLatched[12] == 1'b1 & 1 > CurrentRgAdr & NextRgAdr[11] == 4'b0000) ? RgAdr[12] : NextRgAdr[11];
		NextRgAdr[13] <= (InstForDecodeLatched[13] == 1'b1 & 1 > CurrentRgAdr & NextRgAdr[12] == 4'b0000) ? RgAdr[13] : NextRgAdr[12];
		NextRgAdr[14] <= (InstForDecodeLatched[14] == 1'b1 & 1 > CurrentRgAdr & NextRgAdr[13] == 4'b0000) ? RgAdr[14] : NextRgAdr[13];
		NextRgAdr[15] <= (InstForDecodeLatched[14] == 1'b1 & 1 > CurrentRgAdr & NextRgAdr[14] == 4'b0000) ? RgAdr[15] : NextRgAdr[14];
	end
*/
   
   // STM/LDM
   always @(negedge nRESET or posedge CLK)
   begin: StoreMultipleRegisters
      if (nRESET == 1'b0)		// Reset
      begin
         STM_St <= 1'b0;
         nLDM_St0 <= 1'b0;
         LDM_St1 <= 1'b0;
         LDM_St2 <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            STM_St <= ((~STM_St) & IDR_STM & ExecuteInst) | (STM_St & (~LSMStop));
            nLDM_St0 <= ((~nLDM_St0) & IDR_LDM & ExecuteInst) | (nLDM_St0 & (~(LDM_St2 & LSMStopDel)));
            LDM_St1 <= (~LDM_St1) & (~nLDM_St0) & IDR_LDM & ExecuteInst;
            LDM_St2 <= ((~LDM_St2) & LDM_St1) | (LDM_St2 & (~LSMStopDel));
         end
      end
   end
   
   // Update base register for single load/store
   assign UpDBaseRSng = (~P_Latched) | (P_Latched & W_Latched);		// P=0 (post-indexed) / P=1 && W=1 (pre-indexed)
   
   
   always @(negedge nRESET or posedge CLK)
   begin: BaseUpdate
      if (nRESET == 1'b0)		// Reset
      begin
         BaseRegUdate_St <= 1'b0;
         BaseRegWasUdated_St <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            // Second cycle of all load/store instructions TBD
            BaseRegUdate_St <= (~BaseRegUdate_St) & ExecuteInst & (
			((((~STM_St) & IDR_STM) | ((~nLDM_St0) & IDR_LDM)) & W_Latched) | 
			((((~nLDR_St0) & (IDR_LDR | IDR_LDRB | IDR_LDRSB | IDR_LDRH | IDR_LDRSH)) | // W='1'
			((~STR_St) & (IDR_STR | IDR_STRB | IDR_STRH))) & UpDBaseRSng) | 			// P='0' or (P='1' and W='1')
			(((~nLDR_St0) & (IDR_LDRT | IDR_LDRBT)) | 									// Instructions which always use post-index
			((~STR_St) & (IDR_STRT | IDR_STRBT))));
            
            // Flag which indicates that base register was updated (for LDM/STM)
            BaseRegWasUdated_St <= ((~BaseRegWasUdated_St) & BaseRegUdate_St & 
									(LDM_St1 | (STM_St & (~LSMStop)))) | 
									(BaseRegWasUdated_St & (~((LDM_St2 & LSMStopDel) | 	// End of LDM
									(STM_St & LSMStop))));								// End of STM
         end
      end
   end
   
   
   // Note: For Load/Store multiple base update is conrolled only by W bit(bit[21])
   // For Load/Store single base update is controlled by P bit(bit[24]) and W bit(bit[21]),
   // Update takes place if P=0 (post-indexed) or P=1 && W=1 (pre-indexed)
   // P=0 && W=1 -> instructions with translation (and base update!!!)
   
   // Access to the user mode register during LDM/STM instructions
   assign LSMUMR = (InstForDecodeLatched[22:21] == 2'b10) ? 1'b1 : 		// TBD
                   1'b0;
   
   always @(negedge nRESET or posedge CLK)
   begin: UserModeRegAccess
      if (nRESET == 1'b0)		// Reset
         UMRAccess_St <= 1'b0;
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
            UMRAccess_St <= ((~UMRAccess_St) & (((IDR_STM | IDR_LDM) & ExecuteInst) & LSMUMR)) | 	// End of LDM
			(UMRAccess_St & (~((LDM_St2 & LSMStopDel) | (STM_St & LSMStop))));						// End of STM
      end
   end
   
   
   // Multiplications
   
   // MUL/MLAL/SMULL/UMULL/SMLAL/UMLAL
   always @(negedge nRESET or posedge CLK)
   begin: Multiplications
      if (nRESET == 1'b0)		// Reset
      begin
         MUL_St <= 1'b0;
         
         nMLA_St0 <= 1'b0;
         MLA_St1 <= 1'b0;
         MLA_St2 <= 1'b0;
         
         nMULL_St0 <= 1'b0;
         MULL_St1 <= 1'b0;
         MULL_St2 <= 1'b0;
         
         nMLAL_St0 <= 1'b0;
         MLAL_St1 <= 1'b0;
         MLAL_St2 <= 1'b0;
         MLAL_St3 <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            
            // MUL  m*I+S
            MUL_St <= ((~MUL_St) & IDR_MUL & ExecuteInst) | (MUL_St & (~MulResRdy));
            // MLA	I+m*I+S
            nMLA_St0 <= ((~nMLA_St0) & IDR_MLA & ExecuteInst) | (nMLA_St0 & (~(MLA_St2 & MulResRdy)));
            
            MLA_St1 <= (~MLA_St1) & (~nMLA_St0) & IDR_MLA & ExecuteInst;
            
            MLA_St2 <= ((~MLA_St2) & MLA_St1) | (MLA_St2 & (~MulResRdy));
            
            // SMULL/UMULL m*I+I+S
            nMULL_St0 <= ((~nMULL_St0) & (IDR_SMULL | IDR_UMULL) & ExecuteInst) | (nMULL_St0 & (~MULL_St2));
            
            MULL_St1 <= ((~MULL_St1) & (~nMULL_St0) & (IDR_SMULL | IDR_UMULL) & ExecuteInst) | (MULL_St1 & (~MulResRdy));
            
            MULL_St2 <= (~MULL_St2) & MULL_St1 & MulResRdy;
            
            // SMLAL/UMLAL I+m*I+I+S
            nMLAL_St0 <= ((~nMLAL_St0) & (IDR_SMLAL | IDR_UMLAL) & ExecuteInst) | (nMLAL_St0 & (~MLAL_St3));
            
            MLAL_St1 <= (~MLAL_St1) & (~nMLAL_St0) & (IDR_SMLAL | IDR_UMLAL) & ExecuteInst;
            
            MLAL_St2 <= ((~MLAL_St2) & MLAL_St1) | (MLAL_St2 & (~MulResRdy));
            
            MLAL_St3 <= (~MLAL_St3) & MLAL_St2 & MulResRdy;
         end
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Write to PC handling
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Write to PC indicator
   assign WriteToPC = (WriteAdr_Int == CR_PC & WrEn_Int == 1'b1) ? 1'b1 : 
                      1'b0;
   
   // Change of PC because of write to it(branch) is a part of instruction
   // so it can't be separated from this instruction in any manner (interrupt and etc.)
   
   always @(negedge nRESET or posedge CLK)
   begin: WriteToPCStateMachine
      if (nRESET == 1'b0)		// Reset
      begin
         nWrPCSM_St0 <= 1'b0;
         WrPCSM_St1 <= 1'b0;
         WrPCSM_St2 <= 1'b0;
      end
      else 		// Clock
      begin
         if (CLKEN == 1'b1)		// Clock enable
         begin
            nWrPCSM_St0 <= ((~nWrPCSM_St0) & WriteToPC) | (nWrPCSM_St0 & (~WrPCSM_St2));
            WrPCSM_St1 <= (~WrPCSM_St1) & (~nWrPCSM_St0) & WriteToPC;
            WrPCSM_St2 <= WrPCSM_St1;
         end
      end
   end
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // SPSR/CPSR control and data
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Write to CPSR
   assign WriteToCPSR = (IDR_MSR_R | IDR_MSR_I) & ExecuteInst & (~R_Latched);		// MSR (Immediate/Register) writes to CPSR
   
   // Restore CPSR from current SPSR
   // Data processing instruction writes to PC
   assign RestCPSR = (((IDR_SingleCycleDPI & ExecuteInst) | DPIRegSh_St) & S_Latched & WriteToPC) | (LDM_St2 & InstForDecodeLatched[22] & WriteToPC);		// Load multiple instruction writes to PC
   
   // ALU bus input control
   assign PSRDInSel = (IDR_MSR_R | IDR_MSR_I) & ExecuteInst;		// Value will be written to CPSR/SPSR from the ALU Result Bus
   
   // Current program state register input
   assign CPSRIn = (RestCPSR == 1'b1) ? SPSROut : 		// Restore CPSR from SPSR
                   {NFlagOut, NewZFlag, CFlagOut, VFlagOut, 20'h00000, NewIFlag, NewFFlag, NewTFlag, NewMode};
   
   // New values of F,I and T flags
   assign NewFFlag = (ExceptFC == 1'b1 & FIQExcStart == 1'b1) ? 1'b1 : 		// Fast interrupt
                     1'b0;
   assign NewIFlag = (ExceptFC == 1'b1) ? 1'b1 : 		// Exceptions
                     1'b0;
   assign NewTFlag = (ExceptFC == 1'b1) ? 1'b0 : 		// Change of CPU state
                     RmBitZero;
   
   // C flag control for long multiplications
   assign CFlForMul = MULL_St2 | MLAL_St3;		// Last cycle of long multiplication
   
   // Z flag (is generated in a special way during long mutliplications)
   assign NewZFlag = (MULL_St2 == 1'b1 | MLAL_St3 == 1'b1) ? (ZFlagOut & CPSRZFlag) : 		// Last cycle of long multiplications
                     ZFlagOut;
   
   // Write to N,Z,C and V flags
   assign WriteToHiFl = ((IDR_SingleCycleDPI & ExecuteInst) | DPIRegSh_St) & S_Latched;		// Data processing instructions
   
   // Write to C and Z flags by multiplication instructions
   assign MulFlWr = (MUL_St | nMLA_St0 | nMULL_St0 | nMLAL_St0) & S_Latched;
   
	
   // N flag write enable. CPSRNFlWE
   assign CPSRWrEn[31] = (WriteToHiFl == 1'b1 | 
						  RestCPSR == 1'b1 | 
						 (WriteToCPSR == 1'b1 & Mask[3] == 1'b1) | 
						  MulFlWr == 1'b1) ? 1'b1 : 		// Multiplications
						  1'b0;
   
   // Z flag write enable. CPSRZFlWE
   assign CPSRWrEn[30] = (WriteToHiFl == 1'b1 | 
						  RestCPSR == 1'b1 | 
						 (WriteToCPSR == 1'b1 & Mask[3] == 1'b1) | 
						  MulFlWr == 1'b1) ? 1'b1 : 		// Multiplications
                          1'b0;
   
   // C flag write enable. CPSRCFlWE
   assign CPSRWrEn[29] = (WriteToHiFl == 1'b1 | 
						  RestCPSR == 1'b1 | 
						 (WriteToCPSR == 1'b1 & Mask[3] == 1'b1)) ? 1'b1 : 
                          1'b0;
   
   // V flag write enable. CPSRVFlWE
   assign CPSRWrEn[28] = ((IDR_DPIArith == 1'b1 & WriteToHiFl == 1'b1) | 
						   RestCPSR == 1'b1 | 
						  (WriteToCPSR == 1'b1 & Mask[3] == 1'b1)) ? 1'b1 : 
						   1'b0;
   
   assign CPSRWrEn[27:8] = 20'h00000;
   
   // I flag write enable. CPSRIFlWE
   assign  CPSRWrEn[7] = (RestCPSR == 1'b1 | 
					(WriteToCPSR == 1'b1 & CPSRMode != CUserMode & Mask[0] == 1'b1)) ? 1'b1 : 		// Write to CPSR (ignored in User Mode)
                     1'b0;
   
   // F flag write enable. CPSRFFlWE
   assign CPSRWrEn[6] = (RestCPSR == 1'b1 | 
					(WriteToCPSR == 1'b1 & CPSRMode != CUserMode & Mask[0] == 1'b1)) ? 1'b1 : 		// Write to CPSR (ignored in User Mode)
                     1'b0;
   
   // T flag write enable. CPSRTFlWE
   // Branch with exchange (First cycle)
   assign CPSRWrEn[5] = (RestCPSR == 1'b1 | 
						(IDR_BX == 1'b1 & ExecuteInst == 1'b1 & nBranch_St0 == 1'b0) | 
						(WriteToCPSR == 1'b1 & CPSRMode != CUserMode & Mask[0] == 1'b1) | 
						(ExceptFC == 1'b1)) ? 1'b1 : 		// Write to CPSR (ignored in User Mode)
                         1'b0;
   
   assign CPSRWrEn[4:0] = {5{CPSRModeWE}};
   
   // Was done in order to avoid some Aldec(4.2) bug
   //assign CPSRWrEn = {CPSRNFlWE, CPSRZFlWE, CPSRCFlWE, CPSRVFlWE, 20'h00000, CPSRIFlWE, CPSRFFlWE, CPSRTFlWE, {5{CPSRModeWE}} };
   
   // Write to CPSR by MSR !!
   // CPSRWrEn <= (31 downto 24 => Mask(3))&
   //			   (23 downto 16 => Mask(2))&
   //			   (15 downto 8 => Mask(1))&
   //			   (15 downto 8 => Mask(0))&
   
   // Changing of CPU mode
   assign CPSRModeWE = (ExceptFC == 1'b1 | 	// First cycle of exception !!!TBD
						RestCPSR == 1'b1 | 	// Restore CPSR from SPSR
					   (WriteToCPSR == 1'b1 & CPSRMode != CUserMode & Mask[0] == 1'b1)) ? 1'b1 : 	// Write to CPSR (ignored in User Mode)
                        1'b0;
   
   // Saved program state (Move CPSR to SPSR of the new mode)
   assign SPSRIn = CPSROut;		// TBD
   
   // Write enable (mask) for SPSR
   assign SPSRWrMsk = (ExceptFC == 1'b1) ? 4'b1111 : 		// First cycle of exception
                      ((IDR_MSR_I | IDR_MSR_R) == 1'b1 & ExecuteInst == 1'b1 & R_Latched == 1'b1) ? Mask : 		// Write to SPSR
                      4'b0000;		// No write
   
   // PSR mode control
   assign PSRMode = (ExceptFC == 1'b1) ? NewMode : 		// First cycle of the exception
                    CPSRMode;		// TBD
   
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   // Outputs
   // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   // Thumb decoder enable
   assign ThumbDecoderEn = CPSRTFlag;		// TBD
   
   // TBD
   assign WRITE = ((IDR_STR | IDR_STRB | IDR_STRBT | IDR_STRT | IDR_STRH) & 
					ExecuteInst & (~STR_St)) | 
					((IDR_STM & ExecuteInst & (~STM_St)) | (STM_St & (~LSMStop))) | 	// Store multiple
					SWP_St1;	// ???
   
   // Outputs which have internal copies
   assign WrEn = WrEn_Int;
   assign StagnatePipeline = StagnatePipeline_Int;
   assign StagnatePipelineDel = StagnatePipelineDel_Int;
   assign FirstInstFetch = FirstInstFetch_Int;
   assign WriteAdr = WriteAdr_Int;
   
   // TBD (Thumb mode suppport should be added)
   assign SIZE = ((IDR_LDRB | IDR_LDRBT | IDR_STRB | IDR_STRBT | IDR_LDRSB) == 1'b1 & 
				   ExecuteInst == 1'b1 & nLDR_St0 == 1'b0 & STR_St == 1'b0) ? CTS_B : 
				   (((IDR_LDRH | IDR_STRH | IDR_LDRSH) == 1'b1 & ExecuteInst == 1'b1 & nLDR_St0 == 1'b0 & STR_St == 1'b0)) ? CTS_HW : 
					CTS_W;
   
   
   always @(negedge nRESET or posedge CLK)
   begin: AddrReg
      if (nRESET == 1'b0)
         LastAddr <= 32'h00000000;
      else 
      begin
         if (CLKEN == 1'b1)
            LastAddr <= Addr;
      end
   end
   
   assign DataAddrLow = ((Branch_St1 == 1'b1 | Branch_St2 == 1'b1)) ? LastAddr[1:0] : 
                        (((IDR_LDR == 1'b1 | IDR_LDRT == 1'b1) & (LDR_St1 == 1'b1))) ? 2'b00 : 
                        (((IDR_LDRH == 1'b1 | IDR_LDRSH == 1'b1) & (LDR_St1 == 1'b0))) ? {LastAddr[1], 1'b0} : 
                        ((nLDM_St0 == 1'b1)) ? 2'b00 : 
                        LastAddr[1:0];
   
   assign PREEMPTABLE = (StagnatePipeline_Int == 1'b0 & PipelineRefilling == 1'b0 & 
								 StagnatePipelineDel_Int == 1'b0) ? 1'b1 : 
                         1'b0;
   
endmodule

