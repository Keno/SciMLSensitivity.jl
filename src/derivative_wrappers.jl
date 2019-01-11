struct SensitivityAlg{CS,AD,FDT,Jv,Quad,BS} <: DiffEqBase.DEAlgorithm end
Base.@pure function SensitivityAlg(;chunk_size=0,autodiff=true,diff_type=Val{:central},autojacvec=true,quad=true,backsolve=false)
  backsolve && (quad = false)
  SensitivityAlg{chunk_size,autodiff,typeof(diff_type),autojacvec,quad,backsolve}()
end

Base.@pure function determine_chunksize(u,alg::SensitivityAlg)
  determine_chunksize(u,get_chunksize(alg))
end

Base.@pure function determine_chunksize(u,CS)
  if CS != 0
    return CS
  else
    return ForwardDiff.pickchunksize(length(u))
  end
end

Base.@pure alg_autodiff(alg::SensitivityAlg{CS,AD,FDT,Jv,Quad,BS}) where {CS,AD,FDT,Jv,Quad,BS} = AD
Base.@pure get_chunksize(alg::SensitivityAlg{CS,AD,FDT,Jv,Quad,BS}) where {CS,AD,FDT,Jv,Quad,BS} = CS
Base.@pure diff_type(alg::SensitivityAlg{CS,AD,FDT,Jv,Quad,BS}) where {CS,AD,FDT,Jv,Quad,BS} = FDT
Base.@pure get_jacvec(alg::SensitivityAlg{CS,AD,FDT,Jv,Quad,BS}) where {CS,AD,FDT,Jv,Quad,BS} = Jv
Base.@pure isquad(alg::SensitivityAlg{CS,AD,FDT,Jv,Quad,BS}) where {CS,AD,FDT,Jv,Quad,BS} = Quad
Base.@pure isbcksol(alg::SensitivityAlg{CS,AD,FDT,Jv,Quad,BS}) where {CS,AD,FDT,Jv,Quad,BS} = BS

function jacobian!(J::AbstractMatrix{<:Number}, f, x::AbstractArray{<:Number},
                   fx::AbstractArray{<:Number}, alg::SensitivityAlg, jac_config)
  if alg_autodiff(alg)
    ForwardDiff.jacobian!(J, f, fx, x, jac_config)
  else
    DiffEqDiffTools.finite_difference_jacobian!(J, f, x, jac_config)
  end
  nothing
end

"""
  jacobianvec!(Jv, f, x, v, alg, (buffer, seed)) -> nothing

``Jv <- J(f(x))v``
"""
function jacobianvec!(Jv::AbstractArray{<:Number}, f, x::AbstractArray{<:Number},
                      v, alg::SensitivityAlg, config)
  buffer, seed = config
  if alg_autodiff(alg)
    TD = typeof(first(seed))
    T  = typeof(first(seed).partials)
    @. seed = TD(x, T(tuple(v)))
    f(buffer, seed)
    Jv .= ForwardDiff.partials.(buffer, 1)
  else
      error("Jacobian*vector computation is for automatic differentiation only!")
  end
  nothing
end

mutable struct VJacobianWrapper{fType,tType} <: Function
  f::fType
  t::tType
end
function (ff::VJacobianWrapper)(u, p)
  du1 = similar(p, size(u))
  ff.f(du1,u,p,ff.t)
  return du1
end

#https://gist.github.com/jrevels/c165ed338cc7159085238aa54a763fe2
#https://gist.github.com/jrevels/664e2926c01abb15ac6d92fd4a4788c8
"""
  vecjacobian!(vJ, v, f, x, alg, config) -> nothing

``Jv <- v'J(f(x))``
"""
function vecjacobian!(vJ, v, tape, x)
  input = ReverseDiff.input_hook(tape)
  output = ReverseDiff.output_hook(tape)
  ReverseDiff.unseed!(input) # clear any "leftover" derivatives from previous calls
  ReverseDiff.value!(input, x)
  ReverseDiff.forward_pass!(tape)
  ReverseDiff.increment_deriv!(output, v)
  ReverseDiff.reverse_pass!(tape)
  # Note; we could just say `ReverseDiff.deriv(input)` *is* our `vJ`, in which
  # case we could remove this line, and the caller could just query `vJ` from
  # the tape directly via `ReverseDiff.deriv(ReverseDiff.input_hook(tape))`.
  copyto!(vJ, ReverseDiff.deriv(input))
  return nothing
end
function vecjacobian!(vJ, v, tape, u, p)
  tu, tp = ReverseDiff.input_hook(tape)
  output = ReverseDiff.output_hook(tape)
  ReverseDiff.unseed!(tu) # clear any "leftover" derivatives from previous calls
  ReverseDiff.unseed!(tp)
  ReverseDiff.value!(tu, u)
  ReverseDiff.value!(tp, p)
  ReverseDiff.forward_pass!(tape)
  ReverseDiff.increment_deriv!(output, v)
  ReverseDiff.reverse_pass!(tape)
  # Note; we could just say `ReverseDiff.deriv(input)` *is* our `vJ`, in which
  # case we could remove this line, and the caller could just query `vJ` from
  # the tape directly via `ReverseDiff.deriv(ReverseDiff.input_hook(tape))`.
  copyto!(vJ, ReverseDiff.deriv(tp))
  return nothing
end

function build_jac_config(alg,uf,u)
  if alg_autodiff(alg)
    jac_config = ForwardDiff.JacobianConfig(uf,u,u,
                 ForwardDiff.Chunk{determine_chunksize(u,alg)}())
  else
    if alg.diff_type != Val{:complex}
      jac_config = DiffEqDiffTools.JacobianCache(similar(u),similar(u),
                                                 similar(u),diff_type(alg))
    else
      tmp = Complex{eltype(u)}.(u)
      du1 = Complex{eltype(u)}.(du1)
      jac_config = DiffEqDiffTools.JacobianCache(tmp,du1,nothing,diff_type(alg))
    end
  end
  jac_config
end

function build_param_jac_config(alg,uf,u,p)
  if alg_autodiff(alg)
    jac_config = ForwardDiff.JacobianConfig(uf,u,p,
                 ForwardDiff.Chunk{determine_chunksize(p,alg)}())
  else
    if alg.diff_type != Val{:complex}
      jac_config = DiffEqDiffTools.JacobianCache(similar(p),similar(u),
                                                 similar(u),diff_type(alg))
    else
      tmp = Complex{eltype(p)}.(p)
      du1 = Complex{eltype(u)}.(u)
      jac_config = DiffEqDiffTools.JacobianCache(tmp,du1,nothing,diff_type(alg))
    end
  end
  jac_config
end
