require 'elftools'

class RegFile
  def initialize
    @registers = [0] * 33
  end

  def [](key)
    @registers[key]
  end

  def []=(key, value)
    return if key == 0
    @registers[key] = value & 0xFFFFFFFF
  end
end

class CPU
  def initialize
    # RV32I Base Instruction Set
    @ops = {
      LUI: 0b0110111, # load upper immediate
      LOAD:  0b0000011,
      STORE: 0b0100011,

      AUIPC: 0b0010111, # add upper immediate to pc
      BRANCH: 0b1100011,
      JAL:    0b1101111,
      JALR:   0b1100111,

      IMM:    0b0010011,
      OP:     0b0110011,

      MISC:   0b0001111,
      SYSTEM: 0b1110011,
    }.freeze

    @func3 = {
      ADD:    0b000, SUB: 0b000, ADDI: 0b000,
      SLLI:   0b001,
      SLT:    0b010, SLTI: 0b010,
      SLTU:   0b011, SLTIU: 0b011,

      XOR:    0b100, XORI: 0b100,
      SRL:    0b101, SRLI: 0b101, SRA: 0b101, SRAI: 0b101,
      OR:     0b110, ORI: 0b110,
      AND:    0b111, ANDI: 0b111,

      BEQ:    0b000,
      BNE:    0b001,
      BLT:    0b100,
      BGE:    0b101,
      BLTU:   0b110,
      BGEU:   0b111,

      LB:     0b000,
      LH:     0b001,
      LW:     0b010,
      LBU:    0b100,
      LHU:    0b101,

      SB:     0b000,
      SH:     0b001,
      SW:     0b010,

      CSRRW:  0b001,
      CSRRS:  0b010,
      CSRRC:  0b011,
      CSRRWI: 0b101,
      CSRRSI: 0b110,
      CSRRCI: 0b111,

      ECALL:  0
    }.freeze

    @pc        = 32
    @mtvec     = 33
    @registers = nil
    @memory    = nil
    @regnames  = (
      %w(x0 ra sp gp tp) +
        [*0 .. 2].map { |i| "t#{i}" } +
        %w[s0 s1] +
        [*0 .. 7].map { |i| "a#{i}" } +
        [*2 .. 11].map { |i| "s#{i}" } +
        [*3 .. 6].map { |i| "t#{i}" } +
        %w(PC)
    ).freeze
  end

  def reset
    @registers = RegFile.new
    # 16k at 0x80000000
    @memory = "\x00" * 0x04000
  end

  def get_pc_register
    @registers[@pc]
  end

  def set_pc_register(addr)
    @registers[@pc] = addr
  end

  def ws(addr, dat)
    addr -= 0x80000000
    # print("#{addr} #{dat.size}")
    raise "write out of bounds %x" % addr if addr < 0 || addr >= @memory.length
    @memory = @memory[0, addr] + dat + @memory[addr + dat.size .. -1]
    nil
  end

  def r32(addr)
    addr -= 0x80000000
    raise "read out of bounds %x" % addr if addr < 0 || addr >= @memory.length
    @memory[addr, addr + 4].unpack('L<').first
  end

  def dump
    lines = @registers[0 .. 31].each_with_index.each_slice(8).map do |a|
      a.map { |register, i| " %3s: %08x" % [@regnames[i], register] }.join(" ")
    end
    puts lines.join("\n")
    puts "  PC: %08x" % get_pc_register
  end

  def sign_extend(x, l)
    x >> (l - 1) == 1 ? -((1 << l) - x) : x
  end

  def arith(func3, x, y, alt = nil)
    case func3
    when @func3[:ADDI]
      alt ? x - y : x + y
    when @func3[:SLLI]
      x << (y & 0x1f)
    when @func3[:SRLI]
      if alt
        sb  = x >> 31
        out = x >> (y & 0x1f)
        out | (0xFFFFFFFF * sb) << (32 - (y & 0x1f))
      else
        x >> (y & 0x1f)
      end
    when @func3[:ORI]
      x | y
    when @func3[:XORI]
      x ^ y
    when @func3[:ANDI]
      x & y
    when @func3[:SLT]
      sign_extend(x, 32) < sign_extend(y, 32) ? 1 : 0
    when @func3[:SLTU]
      (x & 0xFFFFFFFF) < (y & 0xFFFFFFFF) ? 1 : 0
    else
      dump
      raise "write arith func3: %s" % @func3.key(func3)
    end
  end

  def step
    # ** Instruction Fetch **
    ins  = r32(get_pc_register)
    gibi = ->(s, e) { (ins >> e) & (1 << (s - e + 1)) - 1 }

    # ** Instruction decode and register fetch **
    opcode = @ops.key(gibi.call(6, 0))
    func3  = gibi.call(14, 12)
    func7  = gibi.call(31, 25)
    imm_i  = sign_extend(gibi.call(31, 20), 12)
    imm_s  = sign_extend((gibi.call(31, 25) << 5) | gibi.call(11, 7), 12)
    imm_b  = sign_extend((gibi.call(32, 31) << 12) | (gibi.call(30, 25) << 5) | (gibi.call(11, 8) << 1) | (gibi.call(8, 7) << 11), 13)
    imm_u  = sign_extend(gibi.call(31, 12) << 12, 32)
    imm_j  = sign_extend((gibi.call(32, 31) << 20) | (gibi.call(30, 21) << 1) | (gibi.call(21, 20) << 11) | (gibi.call(19, 12) << 12), 21)

    # register reads
    vs1 = @registers[gibi.call(19, 15)]
    vs2 = @registers[gibi.call(24, 20)]
    vpc = get_pc_register

    # register write set up
    rd               = gibi.call(11, 7)
    pend             = nil
    is_reg_writeback = false
    is_pend_new_pc   = false
    is_load          = false
    is_store         = false
    # puts("%x %8x %s" % [get_pc_register, ins, opcode])

    # ** Execute **
    case opcode
    when :JAL
      # J-type instruction
      pend             = arith(@func3[:ADD], vpc, imm_j, false)
      is_pend_new_pc   = true
      is_reg_writeback = true
    when :JALR
      # I-type instruction
      pend             = arith(@func3[:ADD], vs1, imm_i, false)
      is_pend_new_pc   = true
      is_reg_writeback = true
    when :BRANCH
      # B-type instruction
      pend           = arith(@func3[:ADD], vpc, imm_b, false)
      is_pend_new_pc = cond(func3, vs1, vs2)
    when :AUIPC
      # U-type instruction
      pend             = arith(@func3[:ADD], vpc, imm_u, false)
      is_reg_writeback = true
    when :LUI
      # U-type instruction
      pend             = imm_u
      is_reg_writeback = true
    when :OP
      # R-type instruction
      pend             = arith(func3, vs1, vs2, func7 == 0b0100000)
      is_reg_writeback = true
    when :IMM
      # I-type instruction
      pend             = arith(func3, vs1, imm_i, func3 == @func3[:SRAI] && func7 == 0b0100000)
      is_reg_writeback = true
      # Memory access step
    when :LOAD
      # I-type instruction
      pend             = arith(@func3[:ADD], vs1, imm_i, false)
      is_load          = true
      is_reg_writeback = true
    when :STORE
      # S-type instruction
      pend     = arith(@func3[:ADD], vs1, imm_s, false)
      is_store = true
      # puts("STORE %8x = %x %d" % [pend, value, width])
    when :MISC
      true
    when :SYSTEM
      if func3 == @func3[:CSRRW] && imm_i == -1024
        # hack for test exit
        return false
      elsif func3 == @func3[:ECALL]
        puts "ecall #{@registers[3]}"
        raise "FAILURE IN TEST" if @registers[3] > 1
      end
    else
      dump
      raise "%s is not a valid Ops" % opcode
    end

    # ** Memory Access **
    if is_load
      case func3
      when @func3[:LB]
        pend = sign_extend(r32(pend) & 0xFF, 8)
      when @func3[:LH]
        pend = sign_extend(r32(pend) & 0xFFFF, 16)
      when @func3[:LW]
        pend = r32(pend)
      when @func3[:LBU]
        pend = r32(pend) & 0xFF
      when @func3[:LHU]
        pend = r32(pend) & 0xFFFF
      else
        dump
        raise "%s is not a valid func3" % func3
      end
    elsif is_store
      case func3
      when @func3[:SB]
        ws(pend, [(vs2 & 0xFF)].pack("C"))
      when @func3[:SH]
        ws(pend, [vs2 & 0xFFFF].pack("S_"))
      when @func3[:SW]
        ws(pend, [vs2].pack("I"))
      else
        dump
        raise "%s is not a valid func3" % func3
      end
    end

    # ** Register write back **
    # dump
    if is_pend_new_pc
      @registers[rd] = vpc + 4 if is_reg_writeback
      set_pc_register(pend)
    else
      @registers[rd] = pend if is_reg_writeback
      set_pc_register(vpc + 4)
    end
    true
  end

  def cond(func3, vs1, vs2)
    case func3
    when @func3[:BEQ]
      vs1 == vs2
    when @func3[:BNE]
      vs1 != vs2
    when @func3[:BLT]
      sign_extend(vs1, 32) < sign_extend(vs2, 32)
    when @func3[:BGE]
      sign_extend(vs1, 32) >= sign_extend(vs2, 32)
    when @func3[:BLTU]
      vs1 < vs2
    when @func3[:BGEU]
      vs1 >= vs2
    else
      dump
      raise "write %s func3: %s" % [opcode, @func3.key(func3)]
    end
  end
end

# main
cpu = CPU.new
Dir["riscv-tests/isa/rv32ui-p*"]
  .reject { |x| x.end_with?(".dump") }
  .each do |x|
  File.open(x, 'rb') do |f|
    cpu.reset
    puts("test #{x}")
    e = ELFTools::ELFFile.new(f)
    e.segments.each do |s|
      cpu.ws(s.header[:p_paddr], s.data)
    end
    cpu.set_pc_register(0x80000000)
    while cpu.step
    end
  end
end