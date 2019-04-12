# Pressure correlations for PressureDrop package.


#%% Helper functions

"""
takacs 52

Note that this does not account for slip between liquid phases.
"""
function liquidvelocity_superficial(q_o, q_w, id, B_o, B_w)
    A = π * (id/24.0)^2 #convert id in inches to ft

    if q_o > 0
        WOR = q_w / q_o
        return 6.5e-5 * (q_o + q_w) / A * (B_o/(1 + WOR) + B_w * WOR / (1 + WOR))
    else #100% WC
        return 6.5e-5 * q_w * B_w / A
    end
end


"""
takacs 52

"""
function gasvelocity_superficial(q_o, q_w, GLR, R_s, id, B_g)
    A = π * (id/24.0)^2 #convert id in inches to ft

    if q_o > 0
        WOR = q_w / q_o
        return 1.16e-5 * (q_o + q_w) / A * (GLR - R_s /(1 + WOR)) * B_g
    else #100% WC
        return 1.16e-5 * q_w * (GLR - R_s) * B_g / A
    end
end

# mixture velocity: just v_sg + v_sl


"""
Weighted average for mixture properties.

Does not account for oil slip, mixing effects, fluid expansion, Non-Newtonian behavior of emulsions, etc.
"""
function mixture_properties_simple(q_o, q_w, property_o, property_w)

    return (q_o * property_o + q_w * property_w) / (q_o + q_w)
end


"""
k is epsilon/d, where epsilon = 0.0006ish for new and 0.009ish for used
and epsilon is the absolute roughness in inches
and k is the pipe ID in inches.

Directly uses Moody for laminar flow; uses Chen 1979 correlation for turbulent flow.

Used in place of the Colebrook implicit solution.

Takacs p30
"""
function ChenFrictionFactor(N_Re, id, roughness = 0.01)

    if N_Re <= 2200 #laminar flow boundary ~2000-2300
        return 16 / N_Re
    else #turbulent flow
        k = roughness/id

        x = -4*log10(k/3.7065 - 5.0452/N_Re * log10(k^1.1098 / 2.8257 + (7.149/N_Re)^0.8981))

        return (1/x)^2

    end
end


#%% Beggs and Brill

"""
Beggs and Brill flow pattern as a string ∈ {"segregated", "transition", "distributed", "intermittent"}.

Takes no-slip holdup (λ_l) and mixture Froude number (N_Fr).

Beggs and Brill. Takacs p87.
"""
function BeggsAndBrillFlowMap(λ_l, N_Fr) #graphical test bypassed in test suite--rerun if modifying this function

    if N_Fr < 316 * λ_l ^ 0.302 && N_Fr < 9.25e-4 * λ_l^-2.468
        return "segregated"
    elseif N_Fr >= 9.25e-4 * λ_l^-2.468 && N_Fr < 0.1 * λ_l^-1.452
        return "transition"
    elseif N_Fr >= 316 * λ_l ^ 0.302 || N_Fr >= 0.5 * λ_l^-6.738
        return "distributed"
    else
        return "intermittent"
    end
end
#TODO: see flow pattern definitions at https://wiki.pengtools.com/index.php?title=Beggs_and_Brill_correlation#cite_note-BB1991-2, which
# appear to be more robust.


# Define coefficients tuple a single time #TODO: benchmark and make sure this really is faster than defining inside fn
const BB_coefficients =     (segregated = (a = 0.980, b= 0.4846, c = 0.0868, e = 0.011, f = -3.7680, g = 3.5390, h = -1.6140),
                            intermittent = (a = 0.845, b = 0.5351, c = 0.0173, e = 2.960, f = 0.3050, g = -0.4473, h = 0.0978),
                            distributed = (a = 1.065, b = 0.5824, c = 0.0609),
                            downhill = (e = 4.700, f = -0.3692, g = 0.1244, h = -0.5056) )

"""
Helper function for Beggs and Brill. Returns adjusted liquid holdup, ε_l(α).

Optional Payne et al correction applied to output.

Takes flow pattern (string ∈ {"segregated", "intermittent", "distributed"}), no-slip holdup (λ_l), Froude number (N_Fr),
liquid velocity number (N_lv), angle from horizontal (α, radians), uphill flow (boolean).

Ref Takacs 88.
"""
function BeggsAndBrillAdjustedLiquidHoldup(flowpattern, λ_l, N_Fr, N_lv, α, inclination, uphill_flow, PayneCorrection = true) #TODO: add a test

    if PayneCorrection && uphill_flow
        correctionfactor = 0.924
    elseif PayneCorrection
        correctionfactor = 0.685
    else
        correctionfactor = 1.0
    end

    flow = Symbol(flowpattern)
    a = BB_coefficients[flow][:a]
    b = BB_coefficients[flow][:b]
    c = BB_coefficients[flow][:c]

    ε_l_horizontal = a * λ_l^b / N_Fr^c #liquid holdup assuming horizontal (α = 0 rad)
    ε_l_horizontal = max(ε_l_horizontal, λ_l)

    if α ≈ 0 #horizontal flow
        return ε_l_horizontal
    else #inclined or vertical flow
        if uphill_flow
            if flowpattern == "distributed"
                ψ = 1.0
            else
                e = BB_coefficients[flow][:e]
                f = BB_coefficients[flow][:f]
                g = BB_coefficients[flow][:g]
                h = BB_coefficients[flow][:h]

                C = max( (1 - λ_l) * log(e * λ_l^f * N_lv^g * N_Fr^h), 0)

                if inclination ≈ 0 #vertical flow
                    ψ = 1 + 0.3 * C
                else
                    ψ = 1 + C * (sin(1.8*α) - (1/3) * sin(1.8*α)^3)
                end
            end
        else #downhill flow
            e = BB_coefficients[:downhill][:e]
            f = BB_coefficients[:downhill][:f]
            g = BB_coefficients[:downhill][:g]
            h = BB_coefficients[:downhill][:h]

            C = max( (1 - λ_l) * log(e * λ_l^f * N_lv^g * N_Fr^h), 0)

            if inclination ≈ 0 #vertical flow
                ψ = 1 + 0.3 * C
            else
                ψ = 1 + C * (sin(1.8*α) - (1/3) * sin(1.8*α)^3)
            end
        end

        return ε_l_horizontal * ψ * correctionfactor
    end

end



"""
Documentation here.

Doesn't account for oil/water phase slip.

Currently assumes *outlet-defined* models only, i.e. top-down from wellhead (easy because they always converge to an inlet/BHP); thus, uphill flow corresponds to producers and downhill flow to injectors.

Returns a ΔP in psi.

http://www.fekete.com/san/webhelp/feketeharmony/harmony_webhelp/content/html_files/reference_material/Calculations_and_Correlations/Pressure_Loss_Calculations.htm
for additional ref
"""
function BeggsAndBrill( md, tvd, inclination, id,
                        v_sl, v_sg, ρ_l, ρ_g, σ_l, μ_l, μ_g,
                        roughness, pressure_est,
                        uphill_flow = true, PayneCorrection = true)

    α = (90 - inclination) * π / 180 #inclination in rad measured from horizontal

    #%% flow pattern and holdup:
    v_m = v_sl + v_sg
    λ_l = v_sl / v_m #no-slip liquid holdup
    N_Fr = 0.373 * v_m^2 / id #mixture Froude number #id is pipe diameter in inches
    N_lv = 1.938 * v_sl * (ρ_l / σ_l)^0.25 #liquid velocity number per Duns & Ros

    flowpattern = BeggsAndBrillFlowMap(λ_l, N_Fr)

    if flowpattern == "transition"
        B = (0.1 * λ_l^-1.4516 - N_Fr) / (0.1 * λ_l^-1.4516 - 9.25e-4 * λ_l^-2.468)
        ε_l_seg = BeggsAndBrillAdjustedLiquidHoldup("segregated", λ_l, N_Fr, N_lv, α, inclination, uphill_flow, PayneCorrection)
        ε_l_int = BeggsAndBrillAdjustedLiquidHoldup("intermittent", λ_l, N_Fr, N_lv, α, inclination, uphill_flow, PayneCorrection)
        ε_l_adj = B * ε_l_seg + (1 - B) * ε_l_int
    else
        ε_l_adj = BeggsAndBrillAdjustedLiquidHoldup(flowpattern, λ_l, N_Fr, N_lv, α, inclination, uphill_flow, PayneCorrection)
    end

    #TODO: is adjusted liquid holdup <= 1 enforced elsewhere already?

    #%% friction factor:
    y = λ_l / ε_l_adj^2
    if 1.0 < y < 1.2
        s = log(2.2y - 1.2) #handle the discontinuity
    else
        ln_y = log(y)
        s = ln_y / (-0.0523 + 3.182 * ln_y - 0.872 * ln_y^2 + 0.01853 * ln_y^4)
    end

    fbyfn = exp(s) #f/fₙ

    ρ_ns = ρ_l * λ_l + ρ_g * (1-λ_l) #no-slip density
    μ_ns = μ_l * λ_l + μ_g * (1-λ_l) #no-slip friction in centipoise
    N_Re = 124 * ρ_ns * v_m * id / μ_ns #Reynolds number
    f_n = ChenFrictionFactor(N_Re, id, roughness)
    fric = f_n * fbyfn #friction factor


    #%% core calculation:
    ρ_m = ρ_l * ε_l_adj + ρ_g * (1 - ε_l_adj) #mixture density in lb/ft³

    dpdl_el = (1/144.0) * ρ_m #TODO:re-validate results having removed sin(α) when multiplying by TVD: $(* sin(α)) #elevation component
    friction_effect = uphill_flow ? 1 : -1 #note that friction MUST act against the direction of flow
    dpdl_f = friction_effect * 1.294e-3 * fric * (ρ_ns * v_m^2) / id #frictional component
    E_k = 2.16e-4 * fric * (v_m * v_sg * ρ_ns) / pressure_est #kinetic effects; typically negligible

    dp_dl = (dpdl_el * tvd + dpdl_f * md) / (1 - friction_effect*E_k) #assumes friction and kinetic effects both increase pressure in the same 1D direction

    return dp_dl
end #Beggs and Brill



#%% Hagedorn & Brown
"""
Does not account for inclination or oil/water slip
"""
function HagedornAndBrownLiquidHoldup(pressure_est, id, v_sl, v_sg, ρ_l, μ_l, σ_l)
    N_lv = 1.938 * v_sl * (ρ_l / σ_l)^0.25 #liquid velocity number per Duns & Ros
    N_gv = 1.938 * v_sg * (ρ_l / σ_l)^0.25 #gas velocity number per Duns & Ros; yes, use liquid density & viscosity
    N_d = 120.872 * id/12 * (ρ_l / σ_l)^0.5 #pipe diameter number; uses id in ft
    N_l = 0.15726 * μ_l * (1/(ρ_l * σ_l^3))^0.25 #liquid viscosity number

    CN_l = 0.061 * N_l^3 - 0.0929 * N_l^2 + 0.0505 * N_l + 0.0019 #liquid viscosity coefficient * liquid viscosity number

    H = N_lv / N_gv^0.575 * (pressure_est/14.7)^0.1 * CN_l / N_d #holdup correlation group

    ε_l_by_ψ = sqrt((0.0047 + 1123.32 * H + 729489.64 * H^2)/(1 + 1097.1566 * H + 722153.97 * H^2))

    B = N_gv * N_l^0.38 / N_d^2.14
    ψ = (1.0886 - 69.9473*B + 2334.3497*B^2 - 12896.683*B^3)/(1 - 53.4401*B + 1517.9369*B^2 - 8419.8115*B^3) #Economedes et al 235

    return ψ * ε_l_by_ψ
end #TODO: tests


"""
Does not account for inclination or oil/water slip

Matching the method demonstrated by U Lafayette
"""
function HagedornAndBrownLiquidHoldup_2(pressure_est, id, v_sl, v_sg, ρ_l, μ_l, σ_l)
    N_lv = 1.938 * v_sl * (ρ_l / σ_l)^0.25 #liquid velocity number per Duns & Ros
    N_gv = 1.938 * v_sg * (ρ_l / σ_l)^0.25 #gas velocity number per Duns & Ros; yes, use liquid density & viscosity
    N_d = 120.872 * id/12 * sqrt(ρ_l / σ_l) #pipe diameter number; uses id in ft
    N_l = 0.15726 * μ_l * (1/(ρ_l * σ_l^3))^0.25 #liquid viscosity number

    CN_l = 10^(-2.69851 + 0.15840954*(log(N_l)+3) + -0.55099756*(log(N_l)+3)^2 + 0.54784917*(log(N_l)+3)^3 + -0.12194578*(log(N_l)+3)^4) #liquid viscosity coefficient * liquid viscosity number

    H = N_lv / N_gv^0.575 * (pressure_est/14.7)^0.1 * CN_l / N_d #holdup correlation group

    ε_l_by_ψ = -0.10306578 + 0.617774*(log(CN_l)+6) + -0.632946*(log(CN_l)+6)^2 + 0.29598*(log(CN_l)+6)^3 + -0.0401*(log(CN_l)+6)^4

    B = N_gv * N_l^0.38 / N_d^2.14 #TODO: verify using N_l vs N_lv
    B_index = (B - 0.012) / abs(B - 0.012)
    B_modified = (1 - index)/2 * 0.012 + (1 + index)/2 * B

    ψ = 0.91162574 + -4.82175636*B_modified + 1232.25036621*B_modified^2 + -22253.57617*B_modified^3 + 116174.28125*B_modified^4

    return ψ * ε_l_by_ψ
end #TODO: tests


#=manual example economedes et al
μ_g = 0.0131
Z = 0.935
v_sl = 4.67
v_sg = 8.72
id = 2.259
roughness = 0.0006

ρ_l = 49.49
ρ_g = 2.6
pressure_est = 800

md = 1
tvd = 1
uphill_flow = true
roughness = 0.0006

σ_l = 30
μ_l = 2

=#

"""
"""
function HagedornAndBrownPressureDrop(pressure_est, id, v_sl, v_sg, ρ_l, ρ_g, μ_l, μ_g, σ_l, id_ft, λ_l, md, tvd, uphill_flow, roughness)

    ε_l = HagedornAndBrownLiquidHoldup(pressure_est, id, v_sl, v_sg, ρ_l, μ_l, σ_l)

    if uphill_flow
        ε_l = max(ε_l, λ_l) #correction to original: for uphill flow, true holdup must by definition be >= no-slip holdup
    end

    ρ_m = ρ_l * ε_l + ρ_g * (1 - ε_l) #mixture density in lb/ft³
    massflow = π*(id_ft/2)^2 * (v_sl * ρ_l + v_sg * ρ_g) * 86400 #86400 s/day

    #%% friction factor:
    μ_m = μ_l^ε_l * μ_g^(1-ε_l)
    N_Re = 2.2e-2 * massflow / (id_ft * μ_m)
    fric = ChenFrictionFactor(N_Re, id, roughness)

    #%% core calculation:
    dpdl_el = 1/144.0 * ρ_m
    dpdl_f = 1/144.0 * fric * massflow^2 / (7.413e10 * id_ft^5 *ρ_m)
    #dpdl_kinetic = 2.16e-4 * ρ_m * v_m * (dvm_dh) #neglected except with high mass flow rates

    dp_dl = dpdl_el * tvd + dpdl_f * md #+ dpdl_kinetic * md

    return dp_dl
end


"""
"""
function GriffithWallisPressureDrop(v_sl, v_sg, v_m, ρ_l, ρ_g, μ_l, id_ft, md, tvd, uphill_flow, roughness)
    v_s = 0.8 #assumed slip velocity of 0.8 ft/s -- probably assumes gas in oil bubbles with no water cut or vice versa?
    ε_l = 1 - 0.5 * (1 + v_m / v_s - sqrt((1 + v_m/v_s)^2 - 4*v_sg/v_s))

    if uphill_flow
        ε_l = max(ε_l, λ_l) #correction to original: for uphill flow, true holdup must by definition be >= no-slip holdup
    end

    ρ_m = ρ_l * ε_l + ρ_g * (1 - ε_l) #mixture density in lb/ft³
    massflow = π*(id_ft/2)^2 * (v_sl * ρ_l + v_sg * ρ_g) * 86400 #86400 s/day

    N_Re = 2.2e-2 * massflow / (id_ft * μ_l)
    fric = ChenFrictionFactor(N_Re, id, roughness)

    dpdl_el = 1/144.0 * ρ_m
    dpdl_f = 1/144.0 * fric * massflow^2 / (7.413e10 * id_ft^5 * ρ_l * ε_l^2)
    dpdl = dpdl_el * tvd + dpdl_f * md

    return dpdl
end




"""
Returns ΔP in psi.

Does not incorporate flow regimes. Originally developed for vertical wells.

same args as B&B for interface continuity
"""
function HagedornAndBrown(md, tvd, inclination, id,
                            v_sl, v_sg, ρ_l, ρ_g, σ_l, μ_l, μ_g,
                            roughness, pressure_est,
                            uphill_flow = true, GriffithWallisCorrection = true)

    id_ft = id/12

    v_m = v_sl + v_sg

    #%% holdup:
    λ_l = v_sl / v_m
    λ_g = 1 - λ_l

    if GriffithWallisCorrection
        L_B = max(1.071 - 0.2218 * v_m^2 / id, 0.13) #Griffith bubble flow boundary
        if λ_g <  L_B
            dpdl = GriffithWallisPressureDrop(v_sl, v_sg, v_m, ρ_l, ρ_g, μ_l, id_ft, md, tvd, uphill_flow, roughness)
        else
            dpdl = HagedornAndBrownPressureDrop(pressure_est, id, v_sl, v_sg, ρ_l, ρ_g, μ_l, μ_g, σ_l, id_ft, λ_l, md, tvd, uphill_flow, roughness)
        end
    else #no correction
        dpdl = HagedornAndBrownPressureDrop(pressure_est, id, v_sl, v_sg, ρ_l, ρ_g, μ_l, μ_g, σ_l, id_ft, λ_l, md, tvd, uphill_flow, roughness)
    end

    return dpdl
end #Hagedorn & Brown #TODO: add tests
