using DiffEqSensitivity, OrdinaryDiffEq, Zygote
using RecursiveArrayTools: DiffEqArray
using Test, ForwardDiff
import Tracker, ReverseDiff

function fiip(du,u,p,t)
  du[1] = dx = p[1]*u[1] - p[2]*u[1]*u[2]
  du[2] = dy = -p[3]*u[2] + p[4]*u[1]*u[2]
end
function foop(u,p,t)
  dx = p[1]*u[1] - p[2]*u[1]*u[2]
  dy = -p[3]*u[2] + p[4]*u[1]*u[2]
  [dx,dy]
end
function foop(u::Tracker.TrackedArray,p,t)
  dx = p[1]*u[1] - p[2]*u[1]*u[2]
  dy = -p[3]*u[2] + p[4]*u[1]*u[2]
  Tracker.collect([dx,dy])
end

p = [1.5,1.0,3.0,1.0]; u0 = [1.0;1.0]
prob = ODEProblem(fiip,u0,(0.0,10.0),p)
proboop = ODEProblem(foop,u0,(0.0,10.0),p)

sol = concrete_solve(prob,Tsit5(),abstol=1e-14,reltol=1e-14)
@test sol isa DiffEqArray
sumsol = sum(sol)
@test sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14)) == sumsol
@test sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,sensealg=ForwardDiffSensitivity())) == sumsol
@test sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,sensealg=BacksolveAdjoint())) == sumsol

###
### adjoint
###

_sol = solve(prob,Tsit5(),abstol=1e-14,reltol=1e-14)
ū0,adj = adjoint_sensitivities(_sol,Tsit5(),((out,u,p,t,i) -> out .= -1),0.0:0.1:10,abstol=1e-14,
                                  reltol=1e-14,iabstol=1e-14,ireltol=1e-12)
du01,dp1 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=QuadratureAdjoint())),u0,p)
du02,dp2 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=InterpolatingAdjoint())),u0,p)
du03,dp3 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=BacksolveAdjoint())),u0,p)
du04,dp4 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=TrackerAdjoint())),u0,p)
@test_broken Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ZygoteAdjoint())),u0,p) isa Tuple
du06,dp6 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ReverseDiffAdjoint())),u0,p)

@test ū0 ≈ du01 rtol=1e-12
@test ū0 == du02
@test ū0 ≈ du03 rtol=1e-12
@test ū0 ≈ du04 rtol=1e-12
#@test ū0 ≈ du05 rtol=1e-12
@test ū0 ≈ du06 rtol=1e-12
@test adj ≈ dp1' rtol=1e-12
@test adj == dp2'
@test adj ≈ dp3' rtol=1e-12
@test adj ≈ dp4' rtol=1e-12
#@test adj ≈ dp5' rtol=1e-12
@test adj ≈ dp6' rtol=1e-12

###
### Other Packages
###

du01,dp1 = Tracker.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1)),u0,p)
@test ū0 == du01
@test adj == dp1'

du01,dp1 = ReverseDiff.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1)),(u0,p))
@test ū0 == du01
@test adj == dp1'

###
### forward
###

du06,dp6 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ForwardSensitivity())),u0,p)
du07,dp7 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ForwardDiffSensitivity())),u0,p)
@test_broken du08,dp8 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs = 1:1,sensealg=ForwardSensitivity())),u0,p)
@test_broken du09,dp9 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs = 1:1,sensealg=ForwardDiffSensitivity())),u0,p)

@test du06 === du07 === nothing
@test adj ≈ dp6' rtol=1e-12
@test adj ≈ dp7' rtol=1e-12

ū02,adj2 = Zygote.gradient((u0,p)->sum(Array(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=InterpolatingAdjoint()))[1,:]),u0,p)
du05,dp5 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=InterpolatingAdjoint())),u0,p)
du06,dp6 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.0:0.1:10.0,save_idxs=1:1,sensealg=QuadratureAdjoint())),u0,p)
du07,dp7 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1,sensealg=InterpolatingAdjoint())),u0,p)
du08,dp8 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=InterpolatingAdjoint())),u0,p)
du09,dp9 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1,sensealg=ReverseDiffAdjoint())),u0,p)
du010,dp10 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=TrackerAdjoint())),u0,p)
@test_broken du011,dp11 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=ForwardSensitivity())),u0,p)
@test_broken du012,dp12 = Zygote.gradient((u0,p)->sum(concrete_solve(prob,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=ForwardDiffSensitivity())),u0,p)

@test ū02 ≈ du05 rtol=1e-12
@test ū02 ≈ du06 rtol=1e-12
@test ū02 ≈ du07 rtol=1e-12
@test ū02 ≈ du08 rtol=1e-12
@test ū02 ≈ du09 rtol=1e-12
@test ū02 ≈ du010 rtol=1e-12
@test adj2 ≈ dp5 rtol=1e-12
@test adj2 ≈ dp6 rtol=1e-12
@test adj2 ≈ dp7 rtol=1e-12
@test adj2 ≈ dp8 rtol=1e-12
@test adj2 ≈ dp9 rtol=1e-12
@test adj2 ≈ dp10 rtol=1e-12

###
### OOPs
###

_sol = solve(prob,Tsit5(),abstol=1e-14,reltol=1e-14)
ū0,adj = adjoint_sensitivities(_sol,Tsit5(),((out,u,p,t,i) -> out .= -1),0.0:0.1:10,abstol=1e-14,
                                  reltol=1e-14,iabstol=1e-14,ireltol=1e-12)

###
### adjoint
###

du01,dp1 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=QuadratureAdjoint())),u0,p)
du02,dp2 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=InterpolatingAdjoint())),u0,p)
du03,dp3 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=BacksolveAdjoint())),u0,p)
du04,dp4 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=TrackerAdjoint())),u0,p)
@test_broken Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ZygoteAdjoint())),u0,p) isa Tuple
@test_broken Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ReverseDiffAdjoint())),u0,p)

@test ū0 ≈ du01 rtol=1e-12
@test ū0 ≈ du02 rtol=1e-12
@test ū0 ≈ du03 rtol=1e-12
@test ū0 ≈ du04 rtol=1e-12
@test adj ≈ dp1' rtol=1e-12
@test adj ≈ dp2' rtol=1e-12
@test adj ≈ dp3' rtol=1e-12
@test adj ≈ dp4' rtol=1e-12

###
### forward
###

@test_broken Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ForwardSensitivity())),u0,p) isa Tuple
du07,dp7 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=ForwardDiffSensitivity())),u0,p)

@test du07 === nothing
#@test adj ≈ dp6' rtol=1e-12
@test adj ≈ dp7' rtol=1e-12

ū02,adj2 = Zygote.gradient((u0,p)->sum(Array(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,sensealg=InterpolatingAdjoint()))[1,:]),u0,p)
du05,dp5 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=InterpolatingAdjoint())),u0,p)
du06,dp6 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.0:0.1:10.0,save_idxs=1:1,sensealg=QuadratureAdjoint())),u0,p)
du07,dp7 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1,sensealg=InterpolatingAdjoint())),u0,p)
du08,dp8 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=InterpolatingAdjoint())),u0,p)
@test_broken du09,dp9 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1,sensealg=ReverseDiffAdjoint())),u0,p)
du010,dp10 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=TrackerAdjoint())),u0,p)
@test_broken du011,dp11 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=ForwardSensitivity())),u0,p)
@test_broken du012,dp12 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=ForwardDiffSensitivity())),u0,p)
# Redundent to test aliasing
du013,dp13 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,saveat=0.1,save_idxs=1:1,sensealg=InterpolatingAdjoint())),u0,p)
du014,dp14 = Zygote.gradient((u0,p)->sum(concrete_solve(proboop,Tsit5(),u0,p,abstol=1e-14,reltol=1e-14,save_idxs=1,saveat=0.1,sensealg=InterpolatingAdjoint())),u0,p)


@test ū02 ≈ du05 rtol=1e-12
@test ū02 ≈ du06 rtol=1e-12
@test ū02 ≈ du07 rtol=1e-12
@test ū02 ≈ du08 rtol=1e-12
#@test ū02 ≈ du09 rtol=1e-12
@test ū02 ≈ du010 rtol=1e-12
#@test ū02 ≈ du011 rtol=1e-12
#@test ū02 ≈ du012 rtol=1e-12
@test ū02 ≈ du013 rtol=1e-12
@test ū02 ≈ du014 rtol=1e-12
@test adj2 ≈ dp5 rtol=1e-12
@test adj2 ≈ dp6 rtol=1e-12
@test adj2 ≈ dp7 rtol=1e-12
@test adj2 ≈ dp8 rtol=1e-12
#@test adj2 ≈ dp9 rtol=1e-12
@test adj2 ≈ dp10 rtol=1e-12
#@test adj2 ≈ dp11 rtol=1e-12
#@test adj2 ≈ dp12 rtol=1e-12
@test adj2 ≈ dp13 rtol=1e-12
@test adj2 ≈ dp14 rtol=1e-12

# Handle VecOfArray Derivatives
dp1 = Zygote.gradient((p)->sum(last(concrete_solve(prob,Tsit5(),u0,p,saveat=10.0,abstol=1e-14,reltol=1e-14))),p)[1]
dp2 = ForwardDiff.gradient((p)->sum(last(concrete_solve(prob,Tsit5(),u0,p,saveat=10.0,abstol=1e-14,reltol=1e-14))),p)
@test dp1 ≈ dp2

dp1 = Zygote.gradient((p)->sum(last(concrete_solve(proboop,Tsit5(),u0,p,saveat=10.0,abstol=1e-14,reltol=1e-14))),p)[1]
dp2 = ForwardDiff.gradient((p)->sum(last(concrete_solve(proboop,Tsit5(),u0,p,saveat=10.0,abstol=1e-14,reltol=1e-14))),p)
@test dp1 ≈ dp2