# 来源与许可证

本项目代码MIT。EDF/EDF+格式是既有工作，参见 https://www.edfplus.info/specs/edfplus.html 。独立验证依赖PyEDFlib0.1.42/EDFlib，其许可证由各上游包提供；本项目不将其作为运行时依赖或把它们的实现重新声明为原创。

公开样本来自PhysioNet EEG Motor Movement/Imagery Dataset1.0.0（Gerwin Schalk及同事），DOI10.13026/C28G6P，ODC-By1.0。原文件未随代码分发；tools/fetch-public-eeg.py按固定校验值获取，派生输出manifest保留来源与署名。完整引用与使用边界见docs/PUBLIC-EEG.md和数据集页面。源码MIT不覆盖第三方数据的权利或许可。

本地另核对EEGMAT Subject00_1.edf（PhysioNet eegmat1.0.0，ODC-By1.0）；未随包分发，不把原始采集工作或数据描述列为本项目成果。
