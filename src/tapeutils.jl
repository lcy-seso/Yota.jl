########################################################################
#                 REINDEXING & OP BINARIZATION                         #
########################################################################


function reindex(op::Call, st::Dict)
    new_args = [get(st, x, x) for x in op.args]
    return copy_with(op, args=new_args)
end

reindex(op::AbstractOp, st::Dict) = op


function reindex_fields!(tape::Tape, st::Dict)
    tape.resultid = get(st, tape.resultid, tape.resultid)
    # possibly we also need to reindex .derivs
end


"""
Transform tape so that all calls to *, /, + and - with multiple arguments were split into
binary form, e.g. transform:

*(a, b, c, d)

to

w1 = a * b
w2 = w1 * c
w3 = w2 * d
"""
function binarize_ops(tape::Tape)
    st = Dict()
    new_tape = copy_with(tape; ops=AbstractOp[])
    for (id, op) in enumerate(tape)
        # id == 11 && break
        # println(id)
        new_id = -1 # to be modified in both branches
        _op = reindex(op, st)   # we need both - original op and reindexed _op
        if op isa Call && op.fn in (+, -, *, /) && length(op.args) > 2
            # record first pair of arguments
            arg1_val, arg2_val = tape[op.args[1]].val, tape[op.args[2]].val
            new_val = op.fn(arg1_val, arg2_val)
            new_id = record!(new_tape, Call, new_val, op.fn, _op.args[1:2])
            # record the rest
            for i=3:length(op.args)
                # calculate new value based on current value and value of original ith argument
                new_val = op.fn(new_val, tape[op.args[i]].val)
                # record new binary op with the previous new_id and new argument id
                new_id = record!(new_tape, Call, new_val, op.fn, [new_id, _op.args[i]])
            end
            # st[id] = new_id
        else
            new_id = length(new_tape) + 1
            push!(new_tape, copy_with(_op; id=new_id))
        end
        if id != new_id
            st[id] = new_id
        end
    end
    reindex_fields!(new_tape, st)
    return new_tape
end


########################################################################
#                       PRE- & POST-PROCESSING                         #
########################################################################

"""
Apply a number of transformations to a tape after tracing and before calculating derivatives
"""
function preprocess(tape::Tape)
    tape = binarize_ops(tape)
    return tape
end


"""
Apply a number of transformations after calculating derivatives
"""
function postprocess(tape::Tape)
    return tape
end


########################################################################
#                          HASH & EQUALITY                             #
########################################################################

# note: hash and == don't use operation values and .compiled field
# so different runs of a tape doesn't affect its identity

Base.hash(op::Input, h::UInt) = hash(op.id, h)
Base.hash(op::Constant, h::UInt) = hash(op.id, hash(op.val, h))
Base.hash(op::Assign, h::UInt) = hash(op.id, hash(op.src_id, h))
Base.hash(op::Call, h::UInt) = hash(op.id, hash(op.fn, hash(op.args, h)))


function Base.hash(tape::Tape, h::UInt)
    h = hash(tape.resultid)
    h = hash(tape.derivs, h)
    h = hash(tape.fieldpaths, h)
    h = hash(tape.device, h)
    for op in tape
        h = hash(op, h)
    end
    return h
end


Base.:(==)(op1::Input, op2::Input) = (op1.id == op2.id)
Base.:(==)(op1::Constant, op2::Constant) = (op1.id == op2.id && op1.val == op2.val)
Base.:(==)(op1::Assign, op2::Assign) = (op1.id == op2.id && op1.src_id == op2.src_id)
Base.:(==)(op1::Call, op2::Call) = (op1.id == op2.id && op1.fn == op2.fn && op1.args == op2.args)

function Base.:(==)(tape1::Tape, tape2::Tape)
    return tape1.resultid == tape2.resultid &&
        tape1.derivs == tape2.derivs &&
        tape1.fieldpaths == tape2.fieldpaths &&
        tape1.device == tape2.device &&
        tape1.ops == tape2.ops
end
