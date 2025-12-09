# Virus Inactivation Analysis: Coxsackievirus B5 Free Chlorine Inactivation in Treated Wastewater and Prediction with Machine Learning

A comprehensive statistical analysis pipeline for studying Coxsackievirus B5 (CVB5) inactivation using chlorine disinfection, with a focus on the effects of ammonia, pH, and temperature on virus inactivation kinetics.

## Project Overview

This project performs comprehensive statistical analysis of virus inactivation data, combining experimental data with literature review data to develop predictive models for virus inactivation. The analysis examines CVB5 inactivation under various conditions including with and without ammonia, different pH levels, and temperature ranges. The pipeline includes multiple statistical modeling approaches and advanced machine learning models to predict inactivation rate constants and calculate CT values required for effective disinfection.

## Project Structure

```
Virus_Code/
├── README.md                           # This file
├── Virus_Analysis.ipynb                # Main R notebook containing all analysis code
└── Virus.xlsx                          # Input data file (required)
    ├── Figure_1a                      # Data for CVB5 without ammonia
    ├── Figure_1b                      # Data for CVB5 with ammonia
    └── Lit_Review                      # Literature review data for comparison
```

## Analysis Components

### 1. Our Data Analysis (`Virus_Analysis.ipynb` - Section 1)
- **Data Visualization**: LRV vs. CT plots comparing different ammonia conditions and detection methods
- **Model Fitting**: Multiple models fitted to experimental data to determine the best fit:
  - Log-linear models, Logistic models, Weibull models, Gompertz models, Gamma models, Lognormal models, and Segmented regression
- **Model Selection**: Models compared using AIC/BIC criteria, with segmented regression identified as the best fit
- **Ammonia Impact Analysis**: Quantification of ammonia effects on inactivation parameters (k₁, k₂) and comparison of inactivation rates

### 2. Literature Data Analysis (`Virus_Analysis.ipynb` - Section 2)
- **Rate Constant Extraction**: Calculation of rate constants (k values) from published literature studies
- **Distribution Analysis**: Gamma and lognormal distributions tested on literature data to characterize the distribution of rate constants
- **Comparative Analysis**: Comparison with published literature data showing rate constants across different studies
- **Environmental Factor Analysis**: Comparison across pH and temperature conditions to understand their effects on inactivation

### 3. Predictive Modeling (`Virus_Analysis.ipynb` - Section 3)
- **Combined Dataset**: Uses both experimental data and literature data together
- **Model Development**: Four different modeling approaches implemented and compared:
  - Linear Mixed Model (LMM): Mixed-effects model accounting for study-level variation
  - Random Forest: Non-parametric ensemble learning model
  - Gaussian Process Regression (GPR): Probabilistic regression model
  - Bayesian Analysis: Bayesian hierarchical modeling for uncertainty quantification
- **Model Evaluation**: Comparison of predicted vs. true rate constant values
- **Predictive Applications**: 
  - 4-Log CT Calculations: Conservative (5th percentile) predictions of CT values required for 4-log virus inactivation
  - Grid Predictions: Model predictions across pH (6-10) and temperature (5-25°C) combinations
  - Uncertainty Quantification: Standard errors and confidence intervals for predictions

## Key Features

- **Comprehensive Pipeline**: End-to-end analysis from raw experimental data to publication-ready figures
- **Multiple Modeling Approaches**: Comparison of traditional statistical models and advanced machine learning methods
- **Quality Control**: Model selection using AIC/BIC criteria and cross-validation
- **Reproducible Analysis**: Well-documented code with clear parameter settings
- **Statistical Rigor**: Appropriate statistical tests and model comparison methods
- **Visualization**: Rich plotting capabilities for data exploration and presentation
- **Predictive Capabilities**: Models for predicting inactivation under various environmental conditions

## Key Dependencies

### R Packages
- `dplyr` - Data manipulation
- `ggplot2` - Data visualization
- `tidyverse` - Data science toolkit
- `readxl` - Excel file reading
- `survival` - Tobit analysis and censored data
- `ggpubr` - Publication-ready plots
- `fitdistrplus` - Distribution fitting
- `car` - Applied regression
- `FSA` - Gompertz modeling
- `loo` - Leave-one-out cross-validation
- `brms` - Bayesian regression models
- `ranger` - Fast random forest implementation
- `caret` - Classification and regression training
- `randomForest` - Random forest algorithm
- `merTools` - Mixed-effects regression tools
- `DiceKriging` - Kriging methods
- `GauPro` - Gaussian process regression
- `kernlab` - Kernel-based machine learning
- `lme4` - Linear mixed-effects models
- `segmented` - Segmented regression
- `lmerTest` - Tests for linear mixed-effects models
- `MuMIn` - Multi-model inference

## Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd Virus_Code
   ```

2. **Install R dependencies**:
   ```r
   install.packages(c("dplyr", "ggplot2", "tidyverse", "readxl", "survival", 
                      "ggpubr", "fitdistrplus", "car", "FSA", "loo", "brms", 
                      "ranger", "caret", "randomForest", "merTools", "DiceKriging", 
                      "GauPro", "kernlab", "lme4", "segmented", "lmerTest", "MuMIn"))
   ```

3. **Prepare data files**:
   - Ensure the `Virus.xlsx` file is in the working directory
   - Verify that the Excel file contains the required sheets: `Figure_1a`, `Figure_1b`, and `Lit_Review`

## Usage

1. Open `Virus_Analysis.ipynb` in RStudio or Jupyter with R kernel
2. Update the figure directory path in the notebook if needed:
   ```r
   fig_dir <- '/path/to/your/figures/directory/'
   ```
3. Run the cells for data import and visualization 
4. Execute model development cells for LMM, Random Forest, GPR, and Bayesian models
5. Use models for predictive applications (4-log CT calculations, grid predictions)

## Data Requirements

### Input Data
- **Experimental data**: CVB5 inactivation data with and without ammonia (`Figure_1a`, `Figure_1b`)
- **Literature data**: Published rate constants, pH, and temperatures from multiple studies (`Lit_Review`)

## Analysis Workflow

1. **Data Preprocessing**
   - Import experimental and literature data
   - Data cleaning and filtering
   - Preparation of combined datasets

2. **Model Fitting on Experimental Data**
   - Fit multiple models (log-linear, logistic, Weibull, Gompertz, gamma, lognormal, segmented)
   - Compare models using AIC/BIC criteria
   - Select best-fitting model (segmented regression)

3. **Literature Data Analysis**
   - Extract and process rate constants from published studies
   - Test distribution fits (gamma and lognormal)
   - Compare across studies and environmental conditions

4. **Predictive Model Development**
   - Develop four modeling approaches (LMM, Random Forest, GPR, Bayesian)
   - Train models on combined dataset
   - Evaluate model performance

5. **Predictive Applications**
   - Generate predictions across pH and temperature ranges
   - Calculate conservative CT values for 4-log inactivation
   - Quantify prediction uncertainty

## Results and Outputs

The pipeline generates:

### Data Structures
- **Model comparisons**: AIC/BIC values and model selection results
- **Statistical results**: Model performance metrics and uncertainty estimates
- **Predictions**: Rate constant predictions and CT values for 4-log inactivation across pH and temperature ranges

### Visualizations
- **Data visualization**: LRV vs. CT plots with different ammonia conditions and detection methods (Figure 1)
- **Literature comparisons**: Rate constants across studies and environmental conditions (Figures 2 and 3)
- **Model performance plots**: Predicted vs. true rate constant values for all models (Figure 4)
- **Publication figures**: High-quality plots for manuscripts (Figures 1-4 and supplementary figures S6-S8)

## Citation

If you use this code in your research, please cite appropriately.

## Contact

For questions about this analysis pipeline, please contact the project maintainer Alma Bartholow.

*Last updated: December 2025*
