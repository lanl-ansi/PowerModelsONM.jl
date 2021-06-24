# [Optimal Dispatch Mathematical model](@id opf-math)

Reproduced in part from [PowerModelsDistribution AC-OPF Documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/stable/manual/math-model.html).

The following represents the nonlinear AC optimization problem specification utilized for the [`optimize_dispatch`](@ref optimize_dispatch) algorithm contained within PowerModelsONM.

## Sets

The definitions of the sets involved remain unchanged w.r.t. the balanced OPF problem definition, except for the addition of the conductor set:

```math
\begin{align}
\mbox{sets:} & \nonumber \\
& N \mbox{ - buses}\nonumber \\
& R \mbox{ - references buses}\nonumber \\
& E, E^R \mbox{ - branches, forward and reverse orientation} \nonumber \\
& G, G_i \mbox{ - generators and generators at bus $i$} \nonumber \\
& L, L_i \mbox{ - loads and loads at bus $i$} \nonumber \\
& S, S_i \mbox{ - shunts and shunts at bus $i$} \nonumber \\
& C \mbox{ - conductors} \nonumber \\
\end{align}
```

where the set of conductors $C$ typically equals $\{ a,b,c\}$.

## Data

```math
\begin{align}
\mbox{data:} & \nonumber \\
& S^{gl}_{k,c}, S^{gu}_{k,c} \in \mathbb{C} \;\; \forall k \in G, \forall c \in C \nonumber; \mathbf{S}^{gl}_{k}:= [S^{gl}_{k,c}]_{c \in C}, \mathbf{S}^{gu}_{k} := [S^{gu}_{k,c}]_{c \in C}  \\
& c_{2k}, c_{1k}, c_{0k} \in \mathbb{R} \;\; \forall k \in G \nonumber \\
& v^l_{i,c}, v^u_{i,c} \in \mathbb{R} \;\; \forall i \in N, \forall c \in C \nonumber; \mathbf{v}^l_{i} := [v^l_{i,c}]_{c \in C}, \mathbf{v}^u_{i} := [v^u_{i,c}]_{c \in C} \\
& S^d_{k,c}\in \mathbb{C} \;\; \forall k \in L, \forall c \in C \nonumber; \mathbf{S}^d_{k} := [S^d_{k,c}]_{c \in C} \\
& \mathbf{Y}^s_{k}\in \mathbb{C}^{c\times c} \;\; \forall k \in S \nonumber \\
& \mathbf{Y}_{ij}, \mathbf{Y}^c_{ij}, \mathbf{Y}^c_{ji}\in \mathbb{C}^{c\times c} \;\; \forall (i,j) \in E \nonumber \\
& {s^u}_{ij,c}, \theta^{\Delta l}_{ij,c}, \theta^{\Delta u}_{ij,c} \in \mathbb{R}\;\; \forall (i,j) \in E, \forall c \in C \nonumber, {\mathbf{s}^u}_{ij} := [{s^u}_{ij,c}]_{c \in C} \\
& V^{\text{ref}}_{i,c}  \in \mathbb{C} \;\; \forall r \in R;  \mathbf{V}^{\text{ref}}_{i} =  [V^{\text{ref}}_{i,c}]_{c \in C} \\
\end{align}
```

where the notation $\mathbf{v}^l_{i} := [v^l_{i,c}]_{c \in C}$ reflects that the vector $\mathbf{v}^l_{i}$ is constructed by putting the individual phase values $v^l_{i,c}$ in a vector (in order $a,b,c$).

Alternatively, the series impedance of a line can be written in impedance form:

```math
\mathbf{Z}_{ij} \in \mathbb{C}^{c\times c} \;\; \forall (i,j) \in E \nonumber, \mathbf{Y}_{ij} = ( \mathbf{Z}_{ij})^{-1}
```

where superscript $-1$ indicates the matrix inverse. Note that $\mathbf{Y}_{ij}$ or $\mathbf{Z}_{ij}$ may not be invertible, e.g. in case of single-phase branches in a three-phase grid. In this case the [pseudo-inverse](https://en.wikipedia.org/wiki/Moore%E2%80%93Penrose_inverse) can be used.

## Variables for a Bus Injection Model

```math
\begin{align}
& S^g_{k,c}  \in \mathbb{C} \;\; \forall k\in G, \forall c \in C \nonumber; \mathbf{S}^g_{k} := [S^g_{k,c}]_{c \in C} \\
& V_{i,c}  \in \mathbb{C} \;\; \forall i\in N, \forall c \in C \nonumber; \mathbf{V}_{i} := [V_{i,c}]_{c \in C} \\
& \mathbf{S}_{ij}  \in \mathbb{C}^{c\times c} \;\; \forall (i,j) \in E \cup E^R \\
\end{align}
```

## Mathematical Formulation of a Bus Injection Model

A complete mathematical model is as follows,

```math
\begin{align}
\mbox{minimize: } & \sum_{k \in G} c_{2k} \left( \sum_{c \in C} \Re(S^g_{k,c}) \right)^2 + c_{1k}  \sum_{c \in C} \Re(S^g_{k,c}) + c_{0k} \\
\mbox{subject to: } & \nonumber \\
& \mathbf{V}_{i} = \mathbf{V}^{\text{ref}}_{i}   \;\; \forall r \in R \\
& S^{gl}_{k,c} \leq S^g_{k,c} \leq S^{gu}_{k,c} \;\; \forall k \in G, \forall c \in C  \\
& v^l_{i,c} \leq |V_{i,c}| \leq v^u_{i,c} \;\; \forall i \in N, \forall c \in C \\
& \sum_{\substack{k \in G_i}} \mathbf{S}^g_k - \sum_{\substack{k \in L_i}} \mathbf{S}^d_k - \sum_{\substack{k \in S_i}}  \mathbf{V}_i \mathbf{V}^H_i (\mathbf{Y}^s_k)^H = \sum_{\substack{(i,j)\in E_i \cup E_i^R}} diag(\mathbf{S}_{ij}) \;\; \forall i\in N \\
& \mathbf{S}_{ij} =  {\mathbf{V}_i \mathbf{V}_i^H} \left( \mathbf{Y}_{ij} + \mathbf{Y}^c_{ij}\right)^H - {\mathbf{V}_i \mathbf{V}^H_j} \mathbf{Y}^H_{ij}  \;\; \forall (i,j)\in E \\
& \mathbf{S}_{ji} = \mathbf{V}_j \mathbf{V}_j^H \left( \mathbf{Y}_{ij} + \mathbf{Y}^c_{ji} \right)^H - {\mathbf{V}^H_i \mathbf{V}_j} \mathbf{Y}^H_{ij} \;\; \forall (i,j)\in E \\
& |diag(\mathbf{S}_{ij})| \leq \mathbf{s}^u_{ij} \;\; \forall (i,j) \in E \cup E^R \\
& \theta^{\Delta l}_{ij,c} \leq \angle (V_{i,c} V^*_{j,c}) \leq \theta^{\Delta u}_{ij,c} \;\; \forall (i,j) \in E, \forall c \in C
\end{align}
```
